import ethers, { BigNumber, BigNumberish } from 'ethers'
import * as instructions from './instructions'

type GetFactory = (signer: ethers.Signer) => Promise<ethers.ContractFactory>

export default class HyperSDK {
  /** Ethers signer. */
  public _signer: ethers.Signer
  /** Ethers factory for the Hyper, Decompiler, contract. */
  public _getHyperFactory: (signer: ethers.Signer) => Promise<ethers.ContractFactory>
  /** Ethers factory for the Forwarder contract. */
  public _getForwarderFactory: (signer: ethers.Signer) => Promise<ethers.ContractFactory>
  /** Hyper protocol contract instance. */
  public instance: ethers.Contract | undefined
  /** An intermediary smart contract that forwards the data to a designated Hyper protocol caller. */
  public forwarder: ethers.Contract | undefined

  constructor(signer: ethers.Signer, getHyperFactory: GetFactory, getForwarderFactory: GetFactory) {
    this._signer = signer
    this._getHyperFactory = getHyperFactory
    this._getForwarderFactory = getForwarderFactory
    this.instance = undefined
    this.forwarder = undefined
  }

  get signer(): ethers.Signer {
    return this._signer
  }

  set signer(x: ethers.Signer) {
    this._signer = x
  }

  get getHyperFactory(): GetFactory {
    return this._getHyperFactory
  }

  set getHyperFactory(x: GetFactory) {
    this._getHyperFactory = x
  }

  get getForwarderFactory(): GetFactory {
    return this._getForwarderFactory
  }

  set getForwarderFactory(x: GetFactory) {
    this._getForwarderFactory = x
  }

  /** Deploys the Hyper protocol and forwarder contract. */
  async deploy(...args) {
    let factory = await this.getHyperFactory(this.signer)
    const instance = await factory.deploy(...args)
    this.instance = instance

    factory = await this.getForwarderFactory(this.signer)
    const forwarder = await factory.deploy()
    this.forwarder = forwarder

    return this.instance
  }

  /** Creates a pair, curve, and pool in one transaction. Hardcoded to the first pair/curve */
  createPool(
    asset: string,
    quote: string,
    controller: string,
    priorityFee: number,
    fee: number,
    volatility: number,
    duration: number,
    jit: number,
    maxTick: number,
    price: BigNumber
  ): Promise<any> {
    const magicVariable = 0 // Used in this jump instructions set to reference the recently created pair and curve.
    let { bytes: pairData } = instructions.encodeCreatePair(asset, quote)
    let { bytes: poolData } = instructions.encodeCreatePool(
      magicVariable,
      controller,
      priorityFee,
      fee,
      volatility,
      duration,
      jit,
      maxTick,
      price
    )
    let { hex: data } = instructions.encodeJumpInstruction([pairData, poolData])
    return this.forward(data)
  }

  /** Adds liquidity to a range of ranges to a pool. */
  async allocate(poolId: number, amount: BigNumber) {
    let { hex: data } = instructions.encodeAllocate(false, poolId, amount)
    return this.forward(data)
  }

  /** Removes liquidity from a range of prices. */
  async unallocate(useMax: boolean, poolId: number, amount: BigNumber) {
    let { hex: data } = instructions.encodeUnallocate(useMax, poolId, amount)
    return this.forward(data)
  }

  /** Swaps asset tokens for quote tokens until limit price is reached or order is filled. */
  async swapAssetToQuote(useMax: boolean, poolId: number, amount: BigNumber, limit: BigNumber) {
    const direction = 0
    let { hex: data } = instructions.encodeSwapExactTokens(useMax, poolId, amount, limit, direction)
    return this.forward(data)
  }

  /** Swaps quote tokens for asset tokens until limit price is reached or order is filled. */
  async swapQuoteToAsset(useMax: boolean, poolId: number, amount: BigNumber, limit: BigNumber) {
    const direction = 1
    let { hex: data } = instructions.encodeSwapExactTokens(useMax, poolId, amount, limit, direction)
    return this.forward(data)
  }

  /** Sends a direct call with the signer to Hyper protocol. */
  async send(data: string, value?: BigNumberish): Promise<any> {
    if (typeof this.instance == 'undefined') throw new Error('Hyper not deployed, call deploy().')
    return this.signer.sendTransaction({ to: this.instance.address, value: value ?? BigInt(0), data })
  }

  /** Calls the "pass" function on the forwarder contract, which sends it to Hyper to process. */
  private forward(data: string) {
    if (typeof this.instance == 'undefined' || typeof this.forwarder == 'undefined')
      throw new Error('Hyper not deployed, call deploy().')

    return this.forwarder.pass(this.instance.address, data)
  }
}
