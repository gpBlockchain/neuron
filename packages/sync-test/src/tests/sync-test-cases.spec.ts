import { cleanCkbNode, startCkbMiner, startCkbNodeWithData, stopCkbNode } from '../services/ckb-runner'
import { cleanLightCkbNode, startCkbLightNodeWithConfig, stopLightCkbNode } from '../services/light-runner'
import { backupNeuronCells, startNeuronWithConfig, stopNeuron, waitNeuronSyncSuccess } from '../services/neuron-runner'
import { scheduler } from 'timers/promises'

import { compareNeuronDatabase } from '../services/neuron-sql-server'

import { CKB_CONFIG, fixtures, NEURON_CONFIG_DATA } from './common'

fixtures.forEach((fixture, idx) => {
  describe('sync test', function () {
    beforeEach(async () => {
      console.log('before each')
      await startCkbNodeWithData({
        binPath: CKB_CONFIG.binPath,
        dataPath: fixture.ckbDataDb,
        configPath: CKB_CONFIG.ckbConfigPath,
        decPath: `${fixture.tmpPath}/ckb`,
      })
      await startCkbMiner({
        binPath: CKB_CONFIG.binPath,
        decPath: `${fixture.tmpPath}/ckb`,
      })
      await startCkbLightNodeWithConfig({
        binPath: CKB_CONFIG.binPath,
        configPath: CKB_CONFIG.ckbLightClientConfigPath,
        decPath: `${fixture.tmpPath}/ckb-light-client`,
      })
    })

    it('full node sync  wallet 1', async () => {
      console.log('full node sync start ')
      await startNeuronWithConfig({
        cleanCells: true,
        envPath: fixture.neuronEnv,
        network: { indexJsonPath: NEURON_CONFIG_DATA.networks.dev },
        wallets: {
          walletsPath: fixture.syncAccount.path,
        },
        neuronCodePath: NEURON_CONFIG_DATA.binPath,
        logPath: `${fixture.tmpPath}/neuron-full-node-wallet-${idx}.log`,
      })
      console.log('wait sync ')
      await waitNeuronSyncSuccess(30 * 60)
      await stopNeuron()
      await backupNeuronCells(`${fixture.tmpPath}/fullNode/wallet1`)
      let result = await compareNeuronDatabase(
        fixture.compareFullNodeSqlitePath,
        `${fixture.tmpPath}/fullNode/wallet1/full-${CKB_CONFIG.genesisHash}.sqlite`,
        `${fixture.tmpPath}/fullNode/wallet1`
      )
      expect(result).toEqual(true)
    })

    it('light node sync  wallet 1', async () => {
      await startNeuronWithConfig({
        cleanCells: true,
        envPath: fixture.neuronEnv,
        network: { indexJsonPath: NEURON_CONFIG_DATA.networks.light },
        wallets: {
          walletsPath: fixture.syncAccount.path,
        },
        neuronCodePath: NEURON_CONFIG_DATA.binPath,
        logPath: `${fixture.tmpPath}/neuron-light-node-wallet-${idx}.log`,
      })
      await waitNeuronSyncSuccess(60 * 60)
      await stopNeuron()
      console.log('backupNeuronCells')
      await backupNeuronCells(`${fixture.tmpPath}/lightNode/wallet1`)
      console.log('compareNeuronDatabase')
      const result = await compareNeuronDatabase(
        fixture.compareLightNodeSqlitePath,
        `${fixture.tmpPath}/lightNode/wallet1/light-${CKB_CONFIG.genesisHash}.sqlite`,
        `${fixture.tmpPath}/lightNode/wallet1`
      )
      expect(result).toEqual(true)
    })

    afterEach(async () => {
      await stopCkbNode()
      await stopLightCkbNode()
      await scheduler.wait(3 * 1000)
      await cleanCkbNode(`${fixture.tmpPath}/ckb`)
      await cleanLightCkbNode(`${fixture.tmpPath}/ckb-light-client`)
      await stopNeuron()
    })
  })
})
