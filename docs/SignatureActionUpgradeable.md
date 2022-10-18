# SignatureActionUpgradeable









## Methods

### claimWithSignature

```solidity
function claimWithSignature(ISignatureAction.GenericRequest _req, bytes _signature) external payable returns (address signer)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| _req | ISignatureAction.GenericRequest | undefined |
| _signature | bytes | undefined |

#### Returns

| Name | Type | Description |
|---|---|---|
| signer | address | undefined |

### verify

```solidity
function verify(ISignatureAction.GenericRequest _req, bytes _signature) external view returns (bool success, address signer)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| _req | ISignatureAction.GenericRequest | undefined |
| _signature | bytes | undefined |

#### Returns

| Name | Type | Description |
|---|---|---|
| success | bool | undefined |
| signer | address | undefined |



## Events

### Initialized

```solidity
event Initialized(uint8 version)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| version  | uint8 | undefined |

### RequestExecuted

```solidity
event RequestExecuted(address indexed user, address indexed signer, ISignatureAction.GenericRequest _req)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| user `indexed` | address | undefined |
| signer `indexed` | address | undefined |
| _req  | ISignatureAction.GenericRequest | undefined |


