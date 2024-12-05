module random_draw::pack {

    use std::string::{String, utf8};

    use sui::dynamic_object_field as ofield;
    use sui::dynamic_field as dfield;
    use sui::event;
    use sui::random;
    use sui::transfer::Receiving;

    use random_draw::caps::{PackerCap};
    use random_draw::token::{Token};

    const EIncorrectPool: u64 = 0x300;
    const ETooManyGroups: u64 = 0x301;
    const EGroupIndexOutOfRange: u64 = 0x302;
    const EOutOfTokens: u64 = 0x303;
    const EPoolInWrongState: u64 = 0x304;
    const EWrongVersion: u64 = 0x305;
    const ENotEnoughGroups: u64 = 0x306;
    const ETooManyTokens: u64 = 0x307;

    const VERSION: u64 = 0x0;
    // at most 16 tokens per pack
    const MAX_GROUPS: u8 = 16;
    const MAX_TOKENS_PER_GROUP: u16 = 0xFFFF;

    public struct TokenList has store, drop {
        // tokens values are sequential and is the child name for the object dynamic field,
        // produced by PackTokenPool.token_counters
        tokens: vector<u16>
    }

    public struct PackTokenPool has key, store {
        id: UID,
        group_count: u8,
        // generate a sequential u16 ID for each token added, and use it to create a dynamic field
        // more space-efficient than using the object ID
        token_counters: vector<u16>,
        // if openening is enabled, packs can be opened and tokens withdrawn,
        // but pool can't be modified (Packer adding and removing tokens)
        opening_enabled: bool,
        version: u64,
    }

    public struct Pack has key, store {
        id: UID,
        name: String,
        // ID of the associated PackTokenPool
        pack_token_pool_id: ID,
    }

    // === Events ===

    public struct PackOpened has copy, drop {
        object_id: ID,
        opener: address,
        // tokens that were delivered to the opener
        tokens: vector<ID>,
    }

    /// Module initializer
    fun init(_ctx: &mut TxContext) {
        // nothing to do
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }

    public fun new_pack(name: String, pack_token_pool_id: ID, _: &PackerCap, ctx: &mut TxContext): Pack {
        Pack {
            id: object::new(ctx),
            name: name,
            pack_token_pool_id: pack_token_pool_id,
        }
    }

    public fun new_pack_token_pool(
        group_count: u8,
        _: &PackerCap,
        ctx: &mut TxContext
    ) {
        assert!(group_count < MAX_GROUPS, ETooManyGroups);
        assert!(group_count > 0, ENotEnoughGroups);
        let mut pool = PackTokenPool {
            id: object::new(ctx),
            group_count,
            token_counters: vector::empty(),
            opening_enabled: false,
            version: VERSION,
        };
        let mut group_idx: u8 = 0;
        while (group_idx < group_count) {
            let token_list = TokenList {
                tokens: vector::empty()
            };
            let child_name = build_tokenlist_dynamic_field_name(group_idx);
            dfield::add(&mut pool.id, child_name, token_list);
            group_idx = group_idx + 1;
            pool.token_counters.push_back(0);
        };
        transfer::share_object(pool);
    }

    public fun set_pool_open(self: &mut PackTokenPool, new_state: bool, _: &PackerCap) {
        // enable pack openings.  pool is closed when we're still building it
        // can also close temporarily when we need to withdraw tokens
        assert!(self.version == VERSION, EWrongVersion);
        assert!(self.opening_enabled != new_state, EPoolInWrongState);
        // don't check if opening is not enabled
        if (self.group_count > 1 && !self.opening_enabled) {
            let sizes = self.sizes();
            let first_size = sizes[0];
            let mut i: u8 = 1;
            while (i < self.group_count) {
                assert!(sizes[i as u64] == first_size, EPoolInWrongState);
                i = i + 1;
            }
        };
        self.opening_enabled = new_state;
    }

    public fun increment_version(pool: &mut PackTokenPool, _: &PackerCap) {
        // Increment version of the pool
        // will not allow exceeding current VERSION value
        assert!(pool.version < VERSION, EWrongVersion);
        pool.version = pool.version + 1;
    }

    public fun receive_object_for_pool(
        pool: &mut PackTokenPool,
        sent: Receiving<Token>,
        group_idx: u8,
        _: &PackerCap
    ) {
        assert!(pool.version == VERSION, EWrongVersion);
        // pool must be closed to receive new objects
        assert!(pool.opening_enabled == false, EPoolInWrongState);
        // a token is sent to the PackTokenPool, and this function is called to
        // register the object, adding as a dynamic field to one of the groups.
        assert!(group_idx < pool.group_count, EGroupIndexOutOfRange);
        // check if we have space for more tokens
        assert!(pool.token_counters[group_idx as u64] < MAX_TOKENS_PER_GROUP, ETooManyTokens);
        // receive object and add as a dynamic field
        let token = transfer::public_receive(&mut pool.id, sent);
        let token_counter_val = pool.token_counters.borrow_mut(group_idx as u64);
        *token_counter_val = *token_counter_val + 1;
        let token_child_name = build_token_dynamic_field_name(group_idx, *token_counter_val);
        ofield::add(&mut pool.id, token_child_name, token);
        let child_name = build_tokenlist_dynamic_field_name(group_idx);
        let token_list: &mut TokenList = dfield::borrow_mut(&mut pool.id, child_name);
        token_list.tokens.push_back(*token_counter_val);
    }

    public fun name(self: &Pack): String {
        self.name
    }

    // open a pack and deliver random tokens from each group to the caller.
    // then burn the pack.  this must be an entry function so that another module
    // can't call, inspect the result, then revert if the result is not to it's liking.
    entry fun open_pack(pool: &mut PackTokenPool, pack: Pack, r: &random::Random, ctx: &mut TxContext) {
        // must be in the pack-opening state
        assert!(pool.version == VERSION, EWrongVersion);
        assert!(pool.opening_enabled, EPoolInWrongState);
        // pull a token from each of the groups, and return to the sender,
        // then burn the pack.
        let pool_id = object::id(pool);
        assert!(pack.pack_token_pool_id == pool_id, EIncorrectPool);
        // random draw one for each group-count, and deliver back to the caller,
        // burning the pack passed in
        let mut group_idx: u8 = 0;
        let mut generator = random::new_generator(r, ctx);
        let mut delivered_token_ids: vector<ID> = vector::empty();
        while (group_idx < pool.group_count) {
            let token: Token = withdraw_random_token_from_group(pool, group_idx, &mut generator);
            delivered_token_ids.push_back(object::id(&token));
            transfer::public_transfer(token, tx_context::sender(ctx));
            group_idx = group_idx + 1;
        };
        event::emit(PackOpened {
            object_id: object::id(&pack),
            opener: tx_context::sender(ctx),
            tokens: delivered_token_ids,
        });
        let Pack { id: pack_uid, .. } = pack;
        object::delete(pack_uid);
    }

    public fun sizes(pool: &PackTokenPool): vector<u64>{
        let mut group_idx: u8 = 0;
        let mut sizes: vector<u64> = vector::empty();
        while (group_idx < pool.group_count) {
            let child_name = build_tokenlist_dynamic_field_name(group_idx);
            let token_list: &TokenList = dfield::borrow(&pool.id, child_name);
            let token_count = token_list.tokens.length();
            sizes.push_back(token_count);
            group_idx = group_idx + 1;
        };
        sizes
    }

    fun withdraw_random_token_from_group(
            pool: &mut PackTokenPool,
            group_idx: u8,
            generator: &mut random::RandomGenerator): Token {
        let child_name = build_tokenlist_dynamic_field_name(group_idx);
        let token_list: &mut TokenList = dfield::borrow_mut(&mut pool.id, child_name);
        let token_count = token_list.tokens.length();
        assert!(token_count > 0, EOutOfTokens);
        let random_idx = random::generate_u64_in_range(generator, 0, token_count);
        let token_id: u16;
        if (random_idx == token_list.tokens.length()) {
            token_id = token_list.tokens.pop_back();
        } else {
            token_id = token_list.tokens.swap_remove(random_idx);
        };
        let token_child_field = build_token_dynamic_field_name(group_idx, token_id);
        let token: Token = ofield::remove(&mut pool.id, token_child_field);
        token
    }

    fun build_tokenlist_dynamic_field_name(group_idx: u8): String {
        assert!(group_idx < MAX_GROUPS, EGroupIndexOutOfRange);
        let mut name = utf8(b"g");
        name.append(group_idx.to_string());
        name
    }

    fun build_token_dynamic_field_name(group_idx: u8, token_counter: u16): String {
        // must never collide with build_tokenlist_dynamic_field
        let mut name = utf8(b"t");
        let token_val: u32 = (group_idx as u32) << 16 | (token_counter as u32);
        name.append(token_val.to_string());
        name
    }

}
