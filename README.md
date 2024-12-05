
## Introduction

This is a simple demonstration of a package that allows creation of Packs of Tokens
that can be delivered to a user's wallet. When the user opens the Pack, they
will receive one or more random Tokens from a pool. This can be used as a 
mechanism for delivering random NFTs to users, in an experience similar to 
packs of trading cards.  This mechanism was developed for [Sweet](https://sweet.io).

## Design

The implementation demonstrates several useful Sui capabilities, on-change randomness, 
transferring objects to another object, and using dynamic fields to store large amounts
of data.

There are three basic object types:

- `Token` - a simple object representing a token, with a name.
- `PackTokenPool` - a pool of Tokens split into equal groups, representing the number of tokens in each Pack.
- `Pack` - a simple object with a name and a reference to the PackTokenPool associated with it. It can be exchanged for a set of Tokens.

The PackTokenPool is created with a fixed set of groups. When a Token is added to a
Pool, it is assigned to a group. A unique u16 is assigned to each token, added to a list
of available tokens (as a vector). The list of token IDs is stored to a dynamic field.
The Token is then added as a dynamic object field using
a name derived from the unique u16 assigned to it. This allows for 65,535 tokens per group
to be stored in the Pool. 

When a Pack is opened, a random Token is selected from each group in the Pool, and
returned to the sender. This uses the on-chain Random module to generate a random 
number between 0 and the number of tokens remaining in the list of IDs. The token's ID
is then removed from the list using a `swap_remove` (O(1) operation) and then retrieved
from the dynamic object field. The `swap_remove` provides a flat gas cost, to provide a 
flat gas cost regardless of where in the list the token is withdrawn, to prevent biasing
selection towards a potentially rare and valuable token.

## Usage

A simple unit test is provided, that creates 100 packs of 3 tokens each, and opens
all of them. Note that a consistent random seed will be used when running the tests,
so the results will always be the same.

```shell
$ sui move test
INCLUDING DEPENDENCY Sui
INCLUDING DEPENDENCY MoveStdlib
BUILDING random_draw
Running Move unit tests
[debug] "Publishing contract to '000000000000000000000000000000000000000000000000000000000000aaaa'"
[debug] "Successfully opened user pack"
[debug] "   Received Token #112"
[debug] "   Received Token #260"
[debug] "   Received Token #96"
[debug] "Successfully opened user pack"
[debug] "   Received Token #184"
[debug] "   Received Token #104"
[debug] "   Received Token #213"
...
[debug] "Successfully opened user pack"
[debug] "   Received Token #25"
[debug] "   Received Token #164"
[debug] "   Received Token #42"
[ PASS    ] random_draw::pack_tests::test_open_packs
Test result: OK. Total tests: 1; passed: 1; failed: 0
```