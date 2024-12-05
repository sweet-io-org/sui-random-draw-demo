module random_draw::token {

    use std::string::{String};
    use random_draw::caps::{PackerCap};

    public struct Token has key, store {
        id: UID,
        name: String,
    }

    /// Module initializer
    fun init(_ctx: &mut TxContext) {
        // nothing to do
    }

    public fun new_token(name: String, _: &PackerCap, ctx: &mut TxContext): Token {
        Token {
            id: object::new(ctx),
            name: name,
        }
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }

    public fun name(self: &Token): String {
        self.name
    }

}