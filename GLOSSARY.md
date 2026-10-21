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

**Relayer**:
The off-chain party that submits published rounds to the service. It can delay delivery but cannot choose or forge the output.
_Avoid_: Oracle, prover, operator

**Fulfillment**:
The point when a request's verified round is committed on-chain. It is final.
_Avoid_: Callback completion, delivery

**Delivery**:
The separate attempt to notify the consumer program of a fulfilled request. Its success or failure does not change fulfillment.
_Avoid_: Fulfillment, callback
