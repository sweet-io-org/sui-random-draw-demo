#[test_only]
module random_draw::pack_tests {
    use random_draw::pack;
    use random_draw::caps;
    use random_draw::token;
    use std::debug;
    use std::string::{String, utf8};
    use sui::test_scenario;
    use sui::random;
    use sui::address;

    public fun build_string(parts: &mut vector<String>): String {
        let mut result: String = utf8(b"");
        while (!parts.is_empty()) {
            result.append(parts.remove(0));
        };
        result
    }

    fun deploy_package(scenario: &mut test_scenario::Scenario, owner: address) {
        scenario.next_tx(owner);
        {
            let dbg_string = build_string(&mut vector[
                utf8(b"Publishing contract to '"),
                owner.to_string(),
                utf8(b"'"),
            ]);
            debug::print(&dbg_string);
            caps::test_init(scenario.ctx());
            pack::test_init(scenario.ctx());
        };
    }

    fun set_pack_open_state(scenario: &mut test_scenario::Scenario, owner: address, new_state: bool) {
        scenario.next_tx(owner);
        {
            let packer = scenario.take_from_sender<caps::PackerCap>();
            let mut pack_pool = scenario.take_shared<pack::PackTokenPool>();
            pack_pool.set_pool_open(new_state, &packer);
            scenario.return_to_sender(packer);
            test_scenario::return_shared(pack_pool);
        };
    }

    fun get_pool_sizes(scenario: &mut test_scenario::Scenario, caller: address): vector<u64>
    {
        let sizes: vector<u64>;
        scenario.next_tx(caller);
        {
            let pack_pool = scenario.take_shared<pack::PackTokenPool>();
            sizes = pack_pool.sizes();
            test_scenario::return_shared(pack_pool);
        };
        sizes
    }

    fun create_pack_pool(scenario: &mut test_scenario::Scenario, group_count: u8, owner: address) {
        scenario.next_tx(owner);
        {
            let packer = scenario.take_from_sender<caps::PackerCap>();
            pack::new_pack_token_pool(group_count, &packer, scenario.ctx());
            scenario.return_to_sender(packer);
        };
    }

    fun create_drop(
        scenario: &mut test_scenario::Scenario,
        owner: address,
        token_count: u64,
        group_count: u8)
    {
        create_pack_pool(scenario, group_count, owner);
        let mut i = 0;
        while (i < token_count) {
            let mut j: u8 = 0;
            while (j < group_count) {
                let token_number = (i * (group_count as u64) + (j as u64) + 1);
                let token_name = build_string(&mut vector[
                    utf8(b"Token #"),
                    token_number.to_string(),
                ]);
                scenario.next_tx(owner);
                {
                    let pack_pool = scenario.take_shared<pack::PackTokenPool>();
                    let pack_pool_id = object::id(&pack_pool);
                    let pack_pool_addr = object::id_to_address(&pack_pool_id);
                    let packer_cap = scenario.take_from_sender<caps::PackerCap>();
                    let token = token::new_token(token_name, &packer_cap, scenario.ctx());
                    transfer::public_transfer(token, pack_pool_addr);
                    scenario.return_to_sender(packer_cap);
                    test_scenario::return_shared(pack_pool);
                };
                // recept is not available until the next tx
                scenario.next_tx(owner);
                {
                    let packer_cap = scenario.take_from_sender<caps::PackerCap>();
                    let mut pack_pool = scenario.take_shared<pack::PackTokenPool>();
                    let pack_pool_id = object::id(&pack_pool);
                    let token_receipt = test_scenario::most_recent_receiving_ticket<token::Token>(&pack_pool_id);
                    pack::receive_object_for_pool(&mut pack_pool, token_receipt, j, &packer_cap);
                    scenario.return_to_sender(packer_cap);
                    test_scenario::return_shared(pack_pool);
                };
                j = j + 1;
            };
            i = i + 1;
        };
        let sizes: vector<u64> = get_pool_sizes(scenario, owner);
        let mut grp_idx = 0;
        while (grp_idx < group_count as u64) {
            assert!(sizes[grp_idx] == token_count);
            grp_idx = grp_idx + 1;
        };
    }

    fun create_random_struct(scenario: &mut test_scenario::Scenario) {
        // test-only function to create the shared Random object
        // must come from the system address (@0x0)
        // note that this will always produce the same generator seed & values
        // https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/random.move#L62
        scenario.next_tx(@0x0);
        {
            random::create_for_testing(scenario.ctx());
        };
    }

    fun add_pack(scenario: &mut test_scenario::Scenario, pack_name: String, owner: address, user: address) {
        scenario.next_tx(owner);
        {
            let packer_cap = scenario.take_from_sender<caps::PackerCap>();
            let pool = scenario.take_shared<pack::PackTokenPool>();
            let pool_obj_id = object::id(&pool);
            let pack = pack::new_pack(pack_name, pool_obj_id, &packer_cap, scenario.ctx());
            transfer::public_transfer(pack, user);
            scenario.return_to_sender(packer_cap);
            test_scenario::return_shared(pool);
        };
    }

    fun open_user_pack(scenario: &mut test_scenario::Scenario, user: address, expected_tokens: u64) {
        let initial_tok_count;
        scenario.next_tx(user);
        {
            // calc increase in tokens
            let id_list = scenario.ids_for_sender<token::Token>();
            initial_tok_count = id_list.length();
        };
        scenario.next_tx(user);
        {
            let pack = scenario.take_from_sender<pack::Pack>();
            let mut pack_pool = scenario.take_shared<pack::PackTokenPool>();
            let rand = scenario.take_shared<random::Random>();
            pack_pool.open_pack(pack, &rand, scenario.ctx());
            test_scenario::return_shared(pack_pool);
            test_scenario::return_shared(rand);
        };
        debug::print(&utf8(b"Successfully opened user pack"));
        scenario.next_tx(user);
        {
            let id_list = scenario.ids_for_sender<token::Token>();
            assert!(id_list.length() - initial_tok_count == expected_tokens);
            let mut i = 0;
            while (i < id_list.length()) {
                let token_id = id_list[i];
                let token = scenario.take_from_sender_by_id<token::Token>(token_id);
                let dbg_string = build_string(&mut vector[
                    utf8(b"   Received "),
                    token.name(),
                ]);
                debug::print(&dbg_string);
                scenario.return_to_sender(token);
                i = i + 1;
            };
        };
    }

    #[test]
    fun test_open_packs() {
        let owner = @0xAAAA;  // the owner of the packs
        let user_base_addr = 0xBBBBBBBB;
        let mut scenario = test_scenario::begin(@0x0);
        deploy_package(&mut scenario, owner);
        let token_count: u64 = 100;
        let group_count: u8 = 3;
        create_drop(&mut scenario, owner, token_count, group_count);
        let mut i: u64 = 0;
        // create packs
        while (i < token_count) {
            let pack_name = build_string(&mut vector[
                utf8(b"Pack #"),
                i.to_string(),
            ]);
            let user = address::from_u256((user_base_addr + i) as u256);
            add_pack(&mut scenario, pack_name, owner, user);
            i = i + 1;
        };
        create_random_struct(&mut scenario);
        set_pack_open_state(&mut scenario, owner, true);
        // open the packs, and print name each time
        i = 0;
        while (i < 100) {
            let user = address::from_u256((user_base_addr + i) as u256);
            open_user_pack(&mut scenario, user, group_count as u64);
            i = i + 1;
        };
        scenario.end();
    }

}

