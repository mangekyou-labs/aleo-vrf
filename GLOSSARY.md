# Aleo Randomness Service

This context covers how consumer programs on Aleo request, receive, and use randomness taken from the drand beacon.

## Language

**Beacon**:
The drand network whose threshold BLS signatures are the service's only source of randomness.
_Avoid_: Oracle, prover key, VRF key

**Round**:
One beacon output, identified by its round number and published at a fixed time.
_Avoid_: Epoch, tick, seed

**Consumer program**:
An Aleo program that requests randomness for its own use.
_Avoid_: Consumer contract, client, beneficiary

**Randomness request**:
A consumer program's recorded commitment to a future round, made before that round can be published.
_Avoid_: Job, order

**Handle**:
The pair of a consumer program and a tag of its choosing that names one randomness request. A consumer program can't reuse a handle, and it reads the request's output back by that handle.
_Avoid_: Request ID, key, ticket

**Relayer**:
The trusted off-chain party authorized to submit published rounds to the service. It can delay delivery and could forge a round, but forgery is detectable by audit.
_Avoid_: Oracle, prover, operator

**Relayer payee**:
The address that receives the fee when a request is fulfilled. It is set separately from the relayer, so the key that submits rounds never holds the earned fees.
_Avoid_: Relayer, treasury

**Admin**:
The single out-of-band authority that configures the service and can upgrade its program. It can't submit rounds, and it can only pause new requests, never fulfillment or refunds.
_Avoid_: Owner, operator, relayer

**Fulfillment**:
The point when a request's relayer-submitted round is committed on-chain. It is final.
_Avoid_: Callback completion, delivery

**Output**:
The single value that fulfillment records for a request, bound to its consumer, request and round. Consumer programs derive every value they use from it.
_Avoid_: Random number, seed, result value

**Derived value**:
A value a consumer program computes from an output and its own context, so that one output can yield several independent values.
_Avoid_: Output, sub-seed

**Delivery**:
A consumer program reading a fulfilled request's output through its own entry point, triggered by anyone. The service never calls consumer programs, and a failed delivery does not change fulfillment.
_Avoid_: Fulfillment, callback, push

**Timeout**:
The end state of a request whose round was not fulfilled within the allowed window. A timed-out request can never be fulfilled.
_Avoid_: Expiry, cancellation

**Payer**:
The wallet that signed a request's transaction and funded its fee. Refunds go back to it. It can differ from the consumer program that made the request.
_Avoid_: Requester, sponsor

**Escrow**:
The service program's own public balance, which holds each request's fee from the request until fulfillment pays it to the relayer payee or a timeout refunds it to the payer.
_Avoid_: Treasury, vault, deposit

**Audit**:
An off-chain check, runnable by anyone, that each fulfilled request's stored beacon signature is valid for its round under the beacon's public key, and that its output was derived from that signature.
_Avoid_: Verification (implies an on-chain check)

**Forgery**:
A fulfillment whose stored signature is not the beacon's signature for the request's round, or whose output was not derived from it. Only the relayer (or an upgrade) can cause one, and an audit proves it from public state alone.
_Avoid_: Invalid proof, bad round
