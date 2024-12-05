module random_draw::caps {

    public struct PackerCap has key, store { id: UID }

    #[test_only]
    /// Create a dummy `PackerCap` for testing
    public fun dummy_packer_cap(ctx: &mut TxContext): PackerCap {
        PackerCap {
            id: object::new(ctx),
        }
    }

    #[test_only]
    /// Allow delete of dummy pxkwe cap
    public fun delete_dummy_packer_cap(packer: PackerCap) {
        let PackerCap { id: packer_cap_uid } = packer;
        object::delete(packer_cap_uid);
    }

    public fun burn_packer(packer: PackerCap) {
        // only the minter can be deleted, prevents creation of new tokens only
        let PackerCap { id } = packer;
        object::delete(id);
    }

    // === Module init ===

    fun init(ctx: &mut TxContext) {
        transfer::transfer(PackerCap {
            id: object::new(ctx)
        }, tx_context::sender(ctx));
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }
}
