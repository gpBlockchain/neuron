import fetch from 'cross-fetch'

const RPC_DEBUG = false

// eslint-disable-next-line @typescript-eslint/no-unused-vars
export const startCkbLightNodeWithConfig = async (option: { binPath: string; configPath: string; decPath: string }) => {
  console.log(option)
  await request(1, 'http://localhost:9000', 'new_dev_client', [])
}

export const stopLightCkbNode = async () => {
  await request(1, 'http://localhost:9000', 'stop', [])
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
export const cleanLightCkbNode = async (path: string) => {
  console.log(path)
  await request(1, 'http://localhost:9000', 'new_dev_client', [])
}

const request = async (id: number, ckbIndexerUrl: string, method: string, params?: any): Promise<any> => {
  console.log('RPC_DEBUG_SERVICE:', RPC_DEBUG)
  if (RPC_DEBUG) {
    console.log(
      "curl --location --request POST '" +
        ckbIndexerUrl +
        "' \\\n" +
        "--header 'Content-Type: application/json' \\\n" +
        "--data-raw '{\n" +
        '\t"jsonrpc":"2.0",\n' +
        '\t"method":"' +
        method +
        '",\n' +
        '\t"params":' +
        JSON.stringify(params) +
        ',\n' +
        '\t"id":64\n' +
        "}'"
    )
  }
  const res = await fetch(ckbIndexerUrl, {
    method: 'POST',
    body: JSON.stringify({
      id,
      jsonrpc: '2.0',
      method,
      params,
    }),
    headers: {
      'Content-Type': 'application/json',
    },
  })
  if (res.status !== 200) {
    throw new Error(`light client request failed with HTTP code ${res.status}`)
  }
  const data = await res.json()

  if (data.error !== undefined) {
    if (RPC_DEBUG) {
      console.log()
      console.log(JSON.stringify(data.error))
    }
    throw new Error(`light client request rpc failed with error: ${JSON.stringify(data.error)}`)
  }
  if (RPC_DEBUG) {
    console.log(JSON.stringify(data.result))
  }
  return data.result
}
