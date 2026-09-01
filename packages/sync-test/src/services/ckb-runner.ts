import { BI, RPC } from '@ckb-lumos/lumos'

import { ChildProcess, StdioNull, StdioPipe, spawn } from 'child_process'
import { mkdirSync, cpSync, existsSync } from 'node:fs'
import { extractTarGz, platform, retry, rm } from '../utils/utils'
import path from 'path'

export const CKB_HOST = `127.0.0.1`
export const CKB_RPC_PORT = 8114

export const CKB_RPC_URL = `http://${CKB_HOST}:${CKB_RPC_PORT}`

let ckb: ChildProcess | null = null
let ckbMiner: ChildProcess | null = null

const STOP_TIMEOUT_MS = 30_000

const assertBinaryExists = (binary: string) => {
  if (!existsSync(binary)) {
    throw new Error(`CKB binary does not exist: ${binary}`)
  }
}

const stopProcess = (process: ChildProcess | null, name: string): Promise<void> => {
  if (!process || process.exitCode !== null || process.signalCode !== null) {
    return Promise.resolve()
  }

  return new Promise<void>(resolve => {
    let finished = false
    const finish = () => {
      if (finished) return
      finished = true
      clearTimeout(timer)
      resolve()
    }
    const timer = setTimeout(() => {
      console.warn(`${name}:\tSIGTERM timeout; sending SIGKILL`)
      try {
        process.kill('SIGKILL')
      } catch {}
      finish()
    }, STOP_TIMEOUT_MS)
    process.once('close', finish)
    process.once('exit', finish)
    process.once('error', finish)
    try {
      process.kill('SIGTERM')
    } catch {
      finish()
    }
  })
}

const ckbBinary = (binPath: string): string => {
  const binary = `${binPath}/ckb`
  switch (platform()) {
    case 'win':
      return binary + '.exe'
    case 'mac':
      //todo check intel
      return binary
    default:
      return binary
  }
}

export const startCkbNodeWithData = async (option: {
  binPath: string
  configPath: string
  dataPath: string
  decPath: string
  richIndexer: boolean
}) => {
  if (ckb !== null) {
    console.info(`CKB:\tckb is not closed, close it before start...`)
    await stopCkbNode()
  }
  await cleanCkbNode(option.decPath)
  console.log('start ckb node ')
  const binary = ckbBinary(option.binPath)
  assertBinaryExists(binary)
  mkdirSync(option.decPath, { recursive: true })
  cpSync(option.configPath, option.decPath, { recursive: true })
  await extractTarGz(option.dataPath, path.join(option.decPath, ...['data']))
  console.log('run start ckb cmd')
  const options = ['run', '-C', option.decPath]
  if (option.richIndexer) {
    options.push('--rich-indexer')
  } else {
    options.push('--indexer')
  }
  const stdio: (StdioNull | StdioPipe)[] = ['ignore', 'ignore', 'pipe']
  ckb = spawn(binary, options, { stdio })
  let ckbRpc = new RPC(CKB_RPC_URL)

  const tipBlock = await retry(
    () =>
      ckbRpc.getTipBlockNumber().then(res => {
        if (Number(res) <= 0) return Promise.reject()
        return res
      }),
    {
      timeout: 60_000,
      delay: 250,
      retries: 240,
    }
  )
  console.info('CKB started', BI.from(tipBlock).toNumber())
  await retry(
    () =>
      ckbRpc.getIndexerTip().then(res => {
        console.log('indexer tip block number:', BI.from(res.blockNumber).toNumber())
        if (Number(res.blockNumber) < BI.from(tipBlock).toNumber()) return Promise.reject()
        return res
      }),
    {
      timeout: 120_000,
      delay: 1000,
      retries: 120,
    }
  )
  console.info('CKB started', BI.from(tipBlock).toNumber())
}

export const startCkbMiner = (option: { decPath: string; binPath: string; limit?: number }) => {
  if (ckb == null) {
    console.error(`CKB:\tckb is not started, please start ckb before starting miner...`)
    return
  }
  if (ckbMiner !== null) {
    console.log('ckb miner already start ')
    return
  }
  const binary = ckbBinary(option.binPath)
  assertBinaryExists(binary)
  const options = ['miner', '-C', option.decPath]
  if (option.limit !== undefined) {
    options.push('--limit', option.limit.toString())
  }
  const stdio: (StdioNull | StdioPipe)[] = ['ignore', 'ignore', 'pipe']
  ckbMiner = spawn(binary, options, { stdio })
  console.log('start miner  successful')
}

export const stopCkbNode = async () => {
  console.log('stop ckb node ')
  const miner = ckbMiner
  const node = ckb
  ckbMiner = null
  ckb = null
  await Promise.all([stopProcess(miner, 'CKB miner'), stopProcess(node, 'CKB node')])
}

export const cleanCkbNode = async (decPath: string) => {
  console.log('clean ckb node env:', decPath)
  rm(decPath)
}
