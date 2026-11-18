import * as os from 'os'
import { platform, rm } from '../utils/utils'
import * as path from 'path'
import { cpSync, existsSync, mkdirSync } from 'node:fs'
import { ChildProcess, spawn, spawnSync } from 'child_process'
import * as fs from 'fs'
import { CKB_RPC_URL } from './ckb-runner'
import { BI, RPC } from '@ckb-lumos/lumos'
import { scheduler } from 'timers/promises'
import sqlite3 from 'sqlite3'

const STOP_TIMEOUT_MS = 30_000

let neuron: ChildProcess | null = null
let neuronLogStream: fs.WriteStream | null = null
let stdoutBuffer = ''
let neuronUserDataPath: string | null = null

let syncResult: {
  result: boolean
  syncTipNumTimes: number
  tipNum: number
} = {
  result: false,
  syncTipNumTimes: 0,
  tipNum: 0,
}

export const getNeuronPath = () => {
  if (neuronUserDataPath) {
    return neuronUserDataPath
  }
  switch (platform()) {
    case 'win':
      //C:\Users\linguopeng_112963420\AppData\Roaming\Neuron
      return path.join(os.homedir(), ...['AppData', 'Roaming', 'Neuron'])
    case 'mac':
      //todo check intel
      return path.join(os.homedir(), ...['Library', 'Application Support', 'Neuron'])
    case 'linux':
      return path.join(os.homedir(), ...['.config', 'Neuron'])
    default:
      throw new Error('not support ')
  }
}

export const getNeuronEnvPath = () => {
  switch (platform()) {
    case 'win':
      //C:\Users\linguopeng_112963420\AppData\Roaming\Neuron
      return ['resources', 'app', '.env']
    case 'mac':
      return ['Contents', 'Resources', 'app', '.env']
    case 'linux':
      return ['squashfs-root', 'resources', 'app', '.env']
    default:
      throw new Error('not support ')
  }
}

export const getNeuronStartCmd = () => {
  switch (platform()) {
    case 'win':
      //C:\Users\linguopeng_112963420\AppData\Roaming\Neuron
      return '.\\Neuron.exe'
    case 'mac':
      return './Contents/MacOS/neuron'
    case 'linux':
      return './squashfs-root/AppRun'
    default:
      throw new Error('not support ')
  }
}

export const startNeuronWithConfig = async (option: {
  envPath: string
  network: {
    indexJsonPath: string
    selectNetwork?: string
  }
  wallets: {
    walletsPath: string
    selectWallet?: string
  }
  cleanCells: boolean
  logPath: string
  neuronCodePath: string
  userDataPath?: string
}) => {
  let ckbRpc = new RPC(CKB_RPC_URL)
  let tipNumber = await ckbRpc.getTipBlockNumber()
  syncResult = { result: false, syncTipNumTimes: 0, tipNum: BI.from(tipNumber).toNumber() }
  console.log('start neuron')

  neuronUserDataPath = option.userDataPath ? path.resolve(option.userDataPath) : null

  if (option.cleanCells) {
    cleanNeuronSyncCells()
  }
  const neuronHome = getNeuronPath()
  mkdirSync(path.join(neuronHome, 'networks'), { recursive: true })
  mkdirSync(path.join(neuronHome, 'wallets'), { recursive: true })
  // cp env
  const appEnvPath = path.join(option.neuronCodePath, ...getNeuronEnvPath())
  mkdirSync(path.dirname(appEnvPath), { recursive: true })
  cpSync(option.envPath, appEnvPath)

  // cp network file
  let decPath = path.join(neuronHome, ...['networks', 'index.json'])
  cpSync(option.network.indexJsonPath, decPath)

  // cp wallet file
  cpSync(option.wallets.walletsPath, path.join(neuronHome, ...['wallets']), { recursive: true })

  // start
  const startCommand = getNeuronStartCmd()
  const executable = path.resolve(option.neuronCodePath, startCommand)
  if (!existsSync(executable)) {
    throw new Error(`Neuron executable does not exist: ${executable}`)
  }
  const args = neuronUserDataPath ? [`--user-data-dir=${neuronUserDataPath}`] : []
  neuron = spawn(startCommand, args, {
    cwd: option.neuronCodePath,
    stdio: ['ignore', 'pipe', 'pipe'],
    detached: platform() !== 'win',
    // shell: true,
  })
  const log = fs.createWriteStream(option.logPath)
  neuronLogStream = log
  neuron.stderr &&
    neuron.stderr.on('data', data => {
      log.write(data)
    })
  neuron.stdout &&
    neuron.stdout.on('data', (data: Buffer) => {
      stdoutBuffer += data.toString()
      const lines = stdoutBuffer.split('\n')
      stdoutBuffer = lines.pop() ?? ''
      for (const line of lines) {
        if (!syncResult.result) {
          const regex = /saved synced block #(\d+)/g
          let match: RegExpExecArray | null
          while ((match = regex.exec(line)) !== null) {
            const number = parseInt(match[1], 10)
            console.log(
              `neuron sync:${number},neuron tipNum:${syncResult.tipNum},syncTipNumTimes:${syncResult.syncTipNumTimes}`
            )
            if (number > syncResult.tipNum) {
              syncResult.tipNum = number
              syncResult.syncTipNumTimes += 1
            }
            if (syncResult.syncTipNumTimes >= 3) {
              syncResult.result = true
            }
          }
        }
      }
      log.write(data)
    })
}

export const waitNeuronSyncSuccess = async (retries: number) => {
  const ckbRpc = new RPC(CKB_RPC_URL)
  let currentTip = 0
  for (let i = 0; i < retries; i++) {
    if (syncResult.result) {
      return syncResult.result
    }
    if (i % 5 === 0) {
      const tipNumber = await ckbRpc.getTipBlockNumber()
      currentTip = BI.from(tipNumber).toNumber()
    }
    if (currentTip > 0 && syncResult.syncTipNumTimes > 0 && syncResult.tipNum >= currentTip - 5) {
      syncResult.result = true
      return true
    }
    await scheduler.wait(1000)
  }
  return Promise.reject('waitNeuronSyncSuccess time out ')
}

type DatabaseState = {
  detailPending: number
  cachePending: number
  keyCount: number
  cacheCount: number
  transactionCount: number
}

const getDatabaseState = (databasePath: string): Promise<DatabaseState> =>
  new Promise((resolve, reject) => {
    const database = new sqlite3.Database(databasePath, sqlite3.OPEN_READONLY, error => {
      if (error) {
        reject(error)
      }
    })
    database.get<DatabaseState>(
      `SELECT
         (SELECT COUNT(*) FROM tx_lock
          WHERE lockArgs IN (SELECT publicKeyInBlake160 FROM hd_public_key_info)) AS detailPending,
         (SELECT COUNT(*) FROM indexer_tx_hash_cache WHERE isProcessed = 0) AS cachePending,
         (SELECT COUNT(*) FROM hd_public_key_info) AS keyCount,
         (SELECT COUNT(*) FROM indexer_tx_hash_cache) AS cacheCount,
         (SELECT COUNT(*) FROM "transaction") AS transactionCount`,
      (error, row) => {
        database.close()
        if (error) {
          reject(error)
        } else {
          resolve(row)
        }
      }
    )
  })

export const waitNeuronDatabaseSettled = async (
  databaseFileName: string,
  expectedDatabasePath: string,
  retries: number = 300
) => {
  const databasePath = path.join(getNeuronPath(), 'cells', databaseFileName)
  const expected = await getDatabaseState(expectedDatabasePath)
  for (let retryCount = 0; retryCount < retries; retryCount++) {
    try {
      const state = await getDatabaseState(databasePath)
      if (
        state.detailPending === 0 &&
        state.cachePending === 0 &&
        state.keyCount >= expected.keyCount &&
        state.cacheCount >= expected.cacheCount &&
        state.transactionCount >= expected.transactionCount
      ) {
        console.log(`neuron database settled: ${databaseFileName}`)
        return
      }
      if (retryCount % 5 === 0) {
        console.log(`wait neuron database: current=${JSON.stringify(state)},expected=${JSON.stringify(expected)}`)
      }
    } catch (error) {
      if (retryCount % 5 === 0) {
        console.log(`wait neuron database: ${error}`)
      }
    }
    await scheduler.wait(1000)
  }
  throw new Error(`Neuron database did not settle in ${retries} seconds: ${databasePath}`)
}

export const stopNeuron = async () => {
  console.log('stop neuron')
  const p = neuron
  const log = neuronLogStream
  const userDataPath = neuronUserDataPath
  neuron = null
  neuronLogStream = null
  stdoutBuffer = ''
  syncResult = { result: false, syncTipNumTimes: 0, tipNum: 0 }
  if (!p) {
    return
  }
  await new Promise<void>(resolve => {
    let done = false
    const processGroupId = platform() !== 'win' ? p.pid : undefined
    const kill = (signal: NodeJS.Signals) => {
      try {
        if (processGroupId) {
          process.kill(-processGroupId, signal)
        } else {
          p.kill(signal)
        }
      } catch {}
    }
    const processGroupIsRunning = () => {
      if (!processGroupId) {
        return p.exitCode === null && p.signalCode === null
      }
      try {
        process.kill(-processGroupId, 0)
        return true
      } catch {
        return false
      }
    }
    const finish = () => {
      if (done) return
      done = true
      clearTimeout(timer)
      clearInterval(groupCheck)
      resolve()
    }
    const groupCheck = setInterval(() => {
      if (!processGroupIsRunning()) {
        finish()
      }
    }, 100)
    const timer = setTimeout(() => {
      kill('SIGKILL')
      finish()
    }, STOP_TIMEOUT_MS)
    p.stdout?.removeAllListeners()
    p.stderr?.removeAllListeners()
    if (!processGroupId) {
      p.once('close', finish)
      p.once('exit', finish)
    }
    log?.end()
    console.info('neuron:\tkilling neuron')
    kill('SIGTERM')
    if (!processGroupIsRunning()) {
      finish()
    }
  })
  if (userDataPath && platform() !== 'win') {
    const processPattern = `[u]ser-data-dir=${userDataPath}`
    spawnSync('pkill', ['-TERM', '-f', processPattern])
    await scheduler.wait(1000)
    spawnSync('pkill', ['-KILL', '-f', processPattern])
  }
}

export const cleanNeuronSyncCells = () => {
  rm(path.join(getNeuronPath(), ...['cells']))
}

export const backupNeuronCells = (decPath: string) => {
  cpSync(path.join(getNeuronPath(), ...['cells']), decPath, { recursive: true })
}
