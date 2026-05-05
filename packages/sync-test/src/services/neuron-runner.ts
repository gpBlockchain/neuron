import * as os from 'os'
import { platform, rm } from '../utils/utils'
import * as path from 'path'
import { cpSync } from 'node:fs'
import { ChildProcess, spawn } from 'child_process'
import * as fs from 'fs'
import { CKB_RPC_URL } from './ckb-runner'
import { BI, RPC } from '@ckb-lumos/lumos'
import { scheduler } from 'timers/promises'

const STOP_TIMEOUT_MS = 30_000

let neuron: ChildProcess | null = null
let neuronLogStream: fs.WriteStream | null = null
let stdoutBuffer = ''

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
}) => {
  let ckbRpc = new RPC(CKB_RPC_URL)
  let tipNumber = await ckbRpc.getTipBlockNumber()
  syncResult = { result: false, syncTipNumTimes: 0, tipNum: BI.from(tipNumber).toNumber() }
  console.log('start neuron')

  if (option.cleanCells) {
    cleanNeuronSyncCells()
  }
  // cp env
  cpSync(option.envPath, path.join(option.neuronCodePath, ...getNeuronEnvPath()))

  // cp network file
  let decPath = path.join(getNeuronPath(), ...['networks', 'index.json'])
  cpSync(option.network.indexJsonPath, decPath)

  // cp wallet file
  cpSync(option.wallets.walletsPath, path.join(getNeuronPath(), ...['wallets']), { recursive: true })

  // start
  neuron = spawn(getNeuronStartCmd(), {
    cwd: option.neuronCodePath,
    stdio: ['ignore', 'pipe', 'pipe'],
    // detached: true,
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

export const stopNeuron = async () => {
  console.log('stop neuron')
  const p = neuron
  const log = neuronLogStream
  neuron = null
  neuronLogStream = null
  stdoutBuffer = ''
  syncResult = { result: false, syncTipNumTimes: 0, tipNum: 0 }
  if (!p) {
    return
  }
  return new Promise<void>(resolve => {
    let done = false
    const finish = () => {
      if (done) return
      done = true
      clearTimeout(timer)
      resolve()
    }
    const timer = setTimeout(() => {
      try {
        p.kill('SIGKILL')
      } catch {}
      finish()
    }, STOP_TIMEOUT_MS)
    p.stdout?.removeAllListeners()
    p.stderr?.removeAllListeners()
    p.once('close', finish)
    p.once('exit', finish)
    log?.end()
    console.info('neuron:\tkilling neuron')
    try {
      p.kill('SIGTERM')
    } catch {
      finish()
    }
  })
}

export const cleanNeuronSyncCells = () => {
  rm(path.join(getNeuronPath(), ...['cells']))
}

export const backupNeuronCells = (decPath: string) => {
  cpSync(path.join(getNeuronPath(), ...['cells']), decPath, { recursive: true })
}
