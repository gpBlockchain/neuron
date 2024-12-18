export const CKB_CONFIG = {
  genesisHash: '0x9c96d0b369b5fd42d7e6b30d6dfdb46e32dac7293bf84de9d1e2d11ca7930717',
  ckbConfigPath: 'source/ckb',
  ckbLightClientConfigPath: 'source/ckb-light-client',
  binPath: 'source/bin',
}

export const CKB_CHAIN_DATA = {
  accounts: [
    'brush scan basic know movie next time soccer speak loop balcony describe',
    'equip slim poem depth struggle tonight define stool brave sustain spy cabbage',
  ],
}

export const NEURON_CONFIG_DATA = {
  binPath: 'neuron',
  networks: {
    dev: 'source/neuron/dev-wallet1/dev/networks/index.dev.json',
    light: 'source/neuron/dev-wallet1/dev/networks/index.light.json',
  },
  accounts: {
    account1: {
      path: 'source/neuron/dev-wallet1/dev/wallets',
      wallets: 'wallets.json',
      passwd: 'neuron.123456',
      account: 'aced9a1c-85c8-40eb-811d-9399212a92b9.json',
      walletsSelectId: 'c114f8e1-141f-49b1-937f-db0ab50faee5',
      mm: 'brush scan basic know movie next time soccer speak loop balcony describe',
    },
  },
}

export const fixtures = [
  {
    name: 'Sync account1 with 2000 blocks',
    syncAccount: NEURON_CONFIG_DATA.accounts.account1,
    ckbDataDb: 'source/data/2000/db.2000.tar.gz',
    neuronEnv: 'source/data/2000/.env',
    compareFullNodeSqlitePath:
      'source/data/2000/account1/fullNode/wallet1/cell-0x9c96d0b369b5fd42d7e6b30d6dfdb46e32dac7293bf84de9d1e2d11ca7930717.sqlite',
    compareLightNodeSqlitePath:
      'source/data/2000/account1/lightNode/wallet1/cell-0x9c96d0b369b5fd42d7e6b30d6dfdb46e32dac7293bf84de9d1e2d11ca7930717.sqlite',
    tmpPath: 'tmp/2000',
    richIndexer: false,
  },
  {
    name: 'Sync account1 with 3000 blocks contains xudt data',
    syncAccount: NEURON_CONFIG_DATA.accounts.account1,
    ckbDataDb: 'source/data/xudt.3000/db.3000.xudt.tar.gz',
    neuronEnv: 'source/data/xudt.3000/.env',
    compareFullNodeSqlitePath:
      'source/data/xudt.3000/account1/fullNode/wallet1/cell-0x9c96d0b369b5fd42d7e6b30d6dfdb46e32dac7293bf84de9d1e2d11ca7930717.sqlite',
    compareLightNodeSqlitePath:
      'source/data/xudt.3000/account1/lightNode/wallet1/cell-0x9c96d0b369b5fd42d7e6b30d6dfdb46e32dac7293bf84de9d1e2d11ca7930717.sqlite',
    tmpPath: 'tmp/2800',
    richIndexer: false,
  },
  {
    name: 'Sync account1 with 2000 blocks use rich indexer',
    syncAccount: NEURON_CONFIG_DATA.accounts.account1,
    ckbDataDb: 'source/data/2000/db.2000.tar.gz',
    neuronEnv: 'source/data/2000/.env',
    compareFullNodeSqlitePath:
      'source/data/2000/account1/fullNode/wallet1/cell-0x9c96d0b369b5fd42d7e6b30d6dfdb46e32dac7293bf84de9d1e2d11ca7930717.sqlite',
    compareLightNodeSqlitePath:
      'source/data/2000/account1/lightNode/wallet1/cell-0x9c96d0b369b5fd42d7e6b30d6dfdb46e32dac7293bf84de9d1e2d11ca7930717.sqlite',
    tmpPath: 'tmp/2000-rich',
    richIndexer: true,
  },
  {
    name: 'Sync account1 with 3000 blocks contains xudt data use rich indexer',
    syncAccount: NEURON_CONFIG_DATA.accounts.account1,
    ckbDataDb: 'source/data/xudt.3000/db.3000.xudt.tar.gz',
    neuronEnv: 'source/data/xudt.3000/.env',
    compareFullNodeSqlitePath:
      'source/data/xudt.3000/account1/fullNode/wallet1/cell-0x9c96d0b369b5fd42d7e6b30d6dfdb46e32dac7293bf84de9d1e2d11ca7930717.sqlite',
    compareLightNodeSqlitePath:
      'source/data/xudt.3000/account1/lightNode/wallet1/cell-0x9c96d0b369b5fd42d7e6b30d6dfdb46e32dac7293bf84de9d1e2d11ca7930717.sqlite',
    tmpPath: 'tmp/2800-rich',
    richIndexer: true,
  },
]
