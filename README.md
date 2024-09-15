## Jellybeans Contracts

Jellybeans is an onchain prediction game.

A question with a numeric answer, a predefined pot, and a submission period is given by a set of gamemakers. Users can submit guesses to the answer for a fee until the submission period ends. The nearest answer less than the answer wins the pot. If there is more than one winner, the pot is split evenly.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
