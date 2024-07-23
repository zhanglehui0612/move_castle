module move_castle::core {
    use sui::dynamic_field; // this package adds functionality to add fields after an object has been constructed
    use sui::math; // basic math functions
    use sui::clock::{Self, Clock}; //adds the clock module and struct for time based functionality
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use move_castle::utils;
    use std::u64;
    use sui::tx_context::{sender, TxContext};

    public struct GameStore has key, store {
        id: UID,
        small_castle_count: u64, // 小型城堡数量限制
        middle_castle_count: u64, // 中型城堡数量限制
        big_castle_count: u64, // 大型城堡数量限制
        castle_ids: vector<ID>, // 持有的城堡的id列表
    }


    public struct CastleData has store {
        id: ID, // 标识符，但不保证链上全局唯一
        size: u64, // 城堡大小
        race: u64, // 城堡种族
        level: u64, // 城堡等级
        experience_pool: u64, // 经验池
        economy: Economy, // 城堡金库
        millitary: Millitary, // 士兵
    }

    public struct Economy has store {
        treasury: u64, // 城堡国库中的资金数量
        base_power: u64, // 基础经济实力
        settle_time: u64, // 上次结算经济的时间
        soldier_buff: EconomicBuff, // 士兵可以提供附加经济力，每个士兵将为城堡提供1点附加经济力
        battle_buff: vector<EconomicBuff> // 通过赢得战斗可以累积的增益列表
    }

    public struct EconomicBuff has copy, store, drop {
        debuff: bool, // 布尔值，用于追踪是增益还是减益
        power: u64, // 增益的力量值
        start: u64, // 增益开始的时间
        end: u64 // 增益结束的时间
    }

    public struct Millitary has store {
        attack_power: u64, // 城堡的攻击力
        defense_power: u64, // 城堡的防御力
        total_attack_power: u64, // 城堡的总攻击力
        total_defense_power: u64, // 城堡的总防御力
        soldiers: u64, // 城堡中的士兵数量
        battle_cooldown: u64 // 战斗冷却时间（在此期间城堡不能战斗）
    }

    public struct AdminCap has key {
        id: UID
    }

    /// 模块初始化函数
    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap{
            id: object::new(ctx)
        };
        /// 谁部署游戏，谁就有管理权限
        transfer::transfer(admin_cap, sender(ctx));

        let game_store = GameStore{
            id: object::new(ctx),
            small_castle_count: 0,
            middle_castle_count: 0,
            big_castle_count: 0,
            castle_ids: vector::empty<ID>()
        };
        transfer::share_object(game_store);
    }


    /// 初始化城堡数据
    public(package) fun init_castle_data(id: ID, // 城堡ID
                                         size: u64, // 城堡规模
                                         race: u64, // 城堡的种族
                                         current_timestamp: u64, // 当前种族
                                         game_store: &mut GameStore) {// 游戏数据存储
        // 1. 获取初始力量并初始化城堡数据
        let (attack_power, defense_power) = get_initial_attack_defense_power(race);
        let (soldiers_attack_power, soldiers_defense_power) = get_initial_soldiers_attack_defense_power(race, INITIAL_SOLDIERS);
        let castle_data = CastleData {
            id: id,
            size: size,
            race: race,
            level: 1,
            experience_pool: 0,
            economy: Economy {
                treasury: 0,
                base_power: get_initial_economic_power(size), /// 根据城堡大小获取初始经济值
                settle_time: current_timestamp,
                /// 计算战士增益
                soldier_buff: EconomicBuff {
                    debuff: false,
                    power: SOLDIER_ECONOMIC_POWER * INITIAL_SOLDIERS,
                    start: current_timestamp,
                    end: 0
                },
                battle_buff: vector::empty<EconomicBuff>() /// 战斗增益列表
            },
            millitary: Millitary {
                attack_power: attack_power, /// 根据城堡种族设置城堡初始攻击力
                defense_power: defense_power,/// 根据城堡种族设置城堡初始防御力
                total_attack_power: attack_power + soldiers_attack_power, /// 根据种族统计城堡再有士兵的情况下总的攻击力(城堡本身自己有一定的攻击力+士兵也有攻击力)
                total_defense_power: defense_power + soldiers_defense_power, /// 根据种族统计城堡再有士兵的情况下总的防御力
                soldiers: INITIAL_SOLDIERS, /// 城堡中战士数量
                battle_cooldown: current_timestamp  /// 战斗冷却时间
            }
        };

        /// 存储城堡数据
        dynamic_field::add(&mut game_store.id, id, castle_data);

        /// 更新城堡 ID 和城堡数量
        vector::push_back(&mut game_store.castle_ids, id);
        if (size == CASTLE_SIZE_SMALL) {
            game_store.small_castle_count = game_store.small_castle_count + 1;
        } else if (size == CASTLE_SIZE_MIDDLE) {
            game_store.middle_castle_count = game_store.middle_castle_count + 1;
        } else if (size == CASTLE_SIZE_BIG) {
            game_store.big_castle_count = game_store.big_castle_count + 1;
        } else {
            abort 0
        };
    }

    /// 根据种族获取攻击和防守的能力的初始值
    fun get_initial_attack_defense_power(race: u64): (u64, u64) {
        let (attack, defense); // 实例化要返回的两个变量值
        if (race == CASTLE_RACE_HUMAN) {
            (attack, defense) = (INITIAL_ATTCK_POWER_HUMAN, INITIAL_DEFENSE_POWER_HUMAN);
        } else if (race == CASTLE_RACE_ELF) {
            (attack, defense) = (INITIAL_ATTCK_POWER_ELF, INITIAL_DEFENSE_POWER_ELF);
        } else if (race == CASTLE_RACE_ORCS) {
            (attack, defense) = (INITIAL_ATTCK_POWER_ORCS, INITIAL_DEFENSE_POWER_ORCS);
        } else if (race == CASTLE_RACE_GOBLIN) {
            (attack, defense) = (INITIAL_ATTCK_POWER_GOBLIN, INITIAL_DEFENSE_POWER_GOBLIN);
        } else if (race == CASTLE_RACE_UNDEAD) {
            (attack, defense) = (INITIAL_ATTCK_POWER_UNDEAD, INITIAL_DEFENSE_POWER_UNDEAD);
        } else {
            abort 0;
        };

        (attack, defense)
    }

    /// 根据种族和战士获取战士初始攻击和防御力
    fun get_initial_soldiers_attack_defense_power(race: u64, soldiers: u64): (u64, u64) {
        /// 根据种族获取战士的攻击力和防御力
        let (attack, defense) = get_castle_soldier_attack_defense_power(race);
        /// 根据战士数量总量，计算总的攻击力和防御力
        (attack * soldiers, defense * soldiers)
    }

    /// 根据城堡规模，获取不同级别的城堡初始经济能力
    fun get_initial_economic_power(size: u64): u64 {
        let power;
        if (size == CASTLE_SIZE_SMALL) {
            power = INITIAL_ECONOMIC_POWER_SMALL_CASTLE;
        } else if (size == CASTLE_SIZE_MIDDLE) {
            power = INITIAL_ECONOMIC_POWER_MIDDLE_CASTLE;
        } else if (size == CASTLE_SIZE_BIG) {
            power = INITIAL_ECONOMIC_POWER_BIG_CASTLE;
        } else {
            abort 0
        };
        power
    }

    public fun get_castle_soldier_attack_defense_power(race: u64): (u64, u64) {
        let (soldier_attack_power, soldier_defense_power);
        if (race == CASTLE_RACE_HUMAN) {
            (soldier_attack_power, soldier_defense_power) = (SOLDIER_ATTACK_POWER_HUMAN, SOLDIER_DEFENSE_POWER_HUMAN)
        } else if (race == CASTLE_RACE_ELF) {
            (soldier_attack_power, soldier_defense_power) = (SOLDIER_ATTACK_POWER_ELF, SOLDIER_DEFENSE_POWER_ELF);
        } else if (race == CASTLE_RACE_ORCS) {
            (soldier_attack_power, soldier_defense_power) = (SOLDIER_ATTACK_POWER_ORCS, SOLDIER_DEFENSE_POWER_ORCS);
        } else if (race == CASTLE_RACE_GOBLIN) {
            (soldier_attack_power, soldier_defense_power) = (SOLDIER_ATTACK_POWER_GOBLIN, SOLDIER_DEFENSE_POWER_GOBLIN);
        } else if (race == CASTLE_RACE_UNDEAD) {
            (soldier_attack_power, soldier_defense_power) = (SOLDIER_ATTACK_POWER_UNDEAD, SOLDIER_DEFENSE_POWER_UNDEAD);
        } else {
            abort 0
        };

        (soldier_attack_power, soldier_defense_power)
    }


    /// 是否允许构建城堡, 根据城堡类型判断该类型的数量是否超过了阈值
    public fun allow_new_castle(size: u64, game_store: &GameStore): bool {
        let allow;
        if (size == CASTLE_SIZE_SMALL) { // check if the size is small
            allow = game_store.small_castle_count < CASTLE_AMOUNT_LIMIT_SMALL; // allow will be true if the count is less than the limit (false if not)
        } else if (size == CASTLE_SIZE_MIDDLE) { // check if the size is middle
            allow = game_store.middle_castle_count < CASTLE_AMOUNT_LIMIT_MIDDLE; // allow will be true if the count is less than the limit (false if not)
        } else if (size == CASTLE_SIZE_BIG) { // check if the size is big
            allow = game_store.big_castle_count < CASTLE_AMOUNT_LIMIT_BIG; // allow will be true if the count is less than the limit (false if not)
        } else {
            abort 0
        };
        allow
    }


    /// 平均每分钟的经济收益
    public fun calculate_economic_benefits(start: u64, end: u64, power: u64): u64 {
        let powers = (end - start) * power;
        /// 172800 - 0 = 172800 seconds
        /// 172800 seconds * 150 power = 25920000
        /// 60 * 1000 = 60000
        /// 25920000 / 60000 = 432 econ
        u64::divide_and_round_up(powers, 60u64 * 1000u64)
    }

    /// 结算城堡的经济，内部方法
    public(package) fun settle_castle_economy_inner(clock: &Clock, castle_data: &mut CastleData) {
        /// 获取到当前交易时间
        let current_timestamp = clock::timestamp_ms(clock);

        /// 1 计算基础经济值
        /// 根据当前时间-上次结算作为时间间隔
        let base_benefits = calculate_economic_benefits(castle_data.economy.settle_time, current_timestamp, castle_data.economy.base_power);
        /// 更新城堡当前的经济财富(已经有的财富+当前基本收益)
        castle_data.economy.treasury = castle_data.economy.treasury + base_benefits;
        /// 更新结算时间
        castle_data.economy.settle_time = current_timestamp;


        /// 2 计算战士收益
        let soldier_benefits = calculate_economic_benefits(castle_data.economy.soldier_buff.start, current_timestamp, castle_data.economy.soldier_buff.power);
        /// 更新城堡当前的经济财富(已经有的财富+当前战士收益)
        castle_data.economy.treasury = castle_data.economy.treasury + soldier_benefits;
        /// 更新战士收益的结算时间
        castle_data.economy.soldier_buff.start = current_timestamp;

        /// 3 计算战斗收益
        if (!vector::is_empty(&castle_data.economy.battle_buff)) {
            let length = vector::length(&castle_data.economy.battle_buff);
            let mut expired_buffs = vector::empty<u64>();
            let mut i = 0;
            /// 遍历数组，遍历的时候需要从数组中对应的位置借用元素，如果是需要改变就是borrow_mut,如果是不能改变就是borrow
            /// 如果是borrow_mut，那么数组肯定要以&mut形式传进来; 如果是borrow,那么数组就要以&形式传进来
            while (i < length) {
                let buff = vector::borrow_mut(&mut castle_data.economy.battle_buff, i);
                let mut battle_benefit;
                /// 如果战斗经济增益结束时间小于当前时间，说明已经停止战斗收益
                if (buff.end <= current_timestamp) {
                    /// 放入到一个到期收益数组中
                    vector::push_back(&mut expired_buffs, i);
                    /// 并且计算这个战斗收益
                    battle_benefit = calculate_economic_benefits(buff.start, buff.end, buff.power);
                } else { /// 如果还没有到期，说明还未结束
                    /// 只计算当前时间到开始时间之间的收益
                    battle_benefit = calculate_economic_benefits(buff.start, current_timestamp, buff.power);
                    /// 并且更新开始时间
                    buff.start = current_timestamp;
                };
                /// 根据战斗收益的性质，决定总收益是需要减去还是增加本次计算的收益
                if (buff.debuff) {
                    castle_data.economy.treasury = castle_data.economy.treasury - battle_benefit;
                } else {
                    castle_data.economy.treasury = castle_data.economy.treasury + battle_benefit;
                };
                i = i + 1; /// 处理下一个位置上战斗收益


                /// 对于到期的战斗收益，需要处理下
                /// 遍历加入到到期收益数组
                while(!vector::is_empty(&expired_buffs)) {
                    /// 该位置上的元素被移除掉，这个数组存储的是它在castle_data.economy.battle_buff中的位置
                    let expired_buff_index = vector::remove(&mut expired_buffs, 0);
                    /// 根据对应的位置从castle_data.economy.battle_buff中移除
                    vector::remove(&mut castle_data.economy.battle_buff, expired_buff_index);
                };
                /// 回收掉或者销毁掉创建的临时的到期数组
                vector::destroy_empty<u64>(expired_buffs);
            }
        }
    }


    /// 结算城堡的经济，包括胜利奖励和失败惩罚
    public(package) fun settle_castle_economy(id: ID, clock: &Clock, game_store: &mut GameStore) {
        settle_castle_economy_inner(clock, dynamic_field::borrow_mut<ID, CastleData>(&mut game_store.id, id));
    }


    /// 根据城堡大小获取士兵限制
    fun get_castle_soldier_limit(size: u64) : u64 {
        let soldier_limit;
        if (size == CASTLE_SIZE_SMALL) {
            soldier_limit = MAX_SOLDIERS_SMALL_CASTLE;
        } else if (size == CASTLE_SIZE_MIDDLE) {
            soldier_limit = MAX_SOLDIERS_MIDDLE_CASTLE;
        } else if (size == CASTLE_SIZE_BIG) {
            soldier_limit = MAX_SOLDIERS_BIG_CASTLE;
        } else {
            abort 0
        };
        soldier_limit
    }


    /// 城堡使用金库招募士兵
    public(package) fun recruit_soldiers (id: ID, count: u64, clock: &Clock, game_store: &mut GameStore) {
        /// 1. 借用城堡数据
        /// 根据GameStore的uid和城堡id获取城堡数据
        let castle_data = dynamic_field::borrow_mut<ID, CastleData>(&mut game_store.id, id);
        /// 2. 检查数量限制
        let final_soldiers = castle_data.millitary.soldiers + count;
        assert!(final_soldiers <= get_castle_soldier_limit(castle_data.size), 0);

        /// 3. 检查金库是否充足
        /// 本次招募需要多少财富值，判断本次招募的财富值是否足够
        let total_soldier_price = SOLDIER_PRICE * count;
        assert!(castle_data.economy.treasury >= total_soldier_price, 0);

        /// 4. 结算经济
        settle_castle_economy_inner(clock, castle_data);

        /// 5. 更新金库和士兵
        /// 扣减城堡当前财富值
        castle_data.economy.treasury = castle_data.economy.treasury - total_soldier_price;
        /// 更新城堡当前战士数量
        castle_data.millitary.soldiers = final_soldiers;

        /// 6. 更新士兵经济实力增益
        castle_data.economy.soldier_buff.power = SOLDIER_ECONOMIC_POWER * final_soldiers;
        castle_data.economy.soldier_buff.start = clock::timestamp_ms(clock);
    }


    /// 随机选择一个城堡作为敌人
    public fun random_battle_target(from_castle: ID, game_store: &GameStore, ctx: &mut TxContext): ID {
        /// 获取当前有多少城堡
        let total_length = vector::length<ID>(&game_store.castle_ids);
        /// 城堡数量少于1,说明城堡数量不足，无法选择敌人
        assert!(total_length > 1, ENotEnoughCastles);

        /// 选择一个随机数
        let mut random_index = utils::random_in_range(total_length, ctx);
        /// 根据随机数选择一个敌人
        let mut target = vector::borrow<ID>(&game_store.castle_ids, random_index);
        /// UID 和 ID：UID 是对象的唯一标识符，包含一个 ID，而 ID 实际上是一个地址。
        /// object::id_to_address：将对象的 ID 转换为地址，便于在不同的上下文中使用地址。
        /// 判断两个城堡地址是不是一样，如果一样的需要从新选择，不能自己选择自己当地人
        while (object::id_to_address(&from_castle) == object::id_to_address(target)) {
            random_index = utils::random_in_range(total_length, ctx); // generates a random index in the range of the length
            target = vector::borrow<ID>(&game_store.castle_ids, random_index); // gets a castle id from the game store at a random index
        };
        /// 再把地址转化为id
        object::id_from_address(object::id_to_address(target))
    }

    /// 取出城堡数据
    public(package) fun fetch_castle_data(id1: ID, id2: ID, game_store: &mut GameStore): (CastleData, CastleData) {
        let castle_data1 = dynamic_field::remove<ID, CastleData>(&mut game_store.id, id1);
        let castle_data2 = dynamic_field::remove<ID, CastleData>(&mut game_store.id, id2);
        (castle_data1, castle_data2)
    }

    /// 获取城堡的战斗冷却时间
    public(package) fun get_castle_battle_cooldown(castle_data: &CastleData): u64 {
        castle_data.millitary.battle_cooldown
    }

    /// 城堡的总士兵攻击力
    public(package) fun get_castle_total_soldiers_attack_power(castle_data: &CastleData): u64 {
        let (soldier_attack_power, _) = get_castle_soldier_attack_defense_power(castle_data.race);
        castle_data.millitary.soldiers * soldier_attack_power
    }

    /// 城堡的总士兵防御力
    public(package) fun get_castle_total_soldiers_defense_power(castle_data: &CastleData): u64 {
        let (_, soldier_defense_power) = get_castle_soldier_attack_defense_power(castle_data.race);
        castle_data.millitary.soldiers * soldier_defense_power
    }

    /// Castle's total attack power (base + soldiers)
    public fun get_castle_total_attack_power(castle_data: &CastleData): u64 {
        castle_data.millitary.attack_power + get_castle_total_soldiers_attack_power(castle_data)
    }

    /// Castle's total defense power (base + soldiers)
    public fun get_castle_total_defense_power(castle_data: &CastleData): u64 {
        castle_data.millitary.defense_power + get_castle_total_soldiers_defense_power(castle_data)
    }

    public fun get_castle_id(castle_data: &CastleData): ID { // returns the castle id from the CastleData object
        castle_data.id // returns castle id
    }

    public fun get_castle_soldiers(castle_data: &CastleData): u64 { // returns the amount of soldiers in the castle from the CastleData object
        castle_data.millitary.soldiers // returns the amount of soldiers
    }

    public fun get_castle_race(castle_data: &CastleData): u64 { // get the castle race by CastleData reference
        castle_data.race
    }

    public fun battle_winner_exp(castle_data: &CastleData): u64 {
        /*
        this function takes a reference to CastleData and returns how much battle xp the winning castle gets
        based on the winner's level. The xp per level is stored in the Constant Vector BATTLE_EXP_GAIN_LEVELS
        */
        *vector::borrow<u64>(&BATTLE_EXP_GAIN_LEVELS, castle_data.level) // borrow gets an immutable reference from the vector at element i (the castle level)
        // in layman terms it's get an immutable value at index i
    }

    public fun get_castle_economic_base_power(castle_data: &CastleData): u64 { // retuns the base econ base power for the castle using a reference to CastleData
        castle_data.economy.base_power // return base power from object
    }

    // Calculate soldiers economic power
    public fun calculate_soldiers_economic_power(count: u64): u64 { // calculates the econ power for the amount of soldiers
        SOLDIER_ECONOMIC_POWER * count // econ power constant for a single soldier * amount of soldiers you want to calculate the power for
    }

    /// 检查种族是否有利
    public fun has_race_advantage(castle_data1: &CastleData, castle_data2: &CastleData): bool { // this function checks if either castle has a race advantage, it gets the data from both castles
        let c1_race = castle_data1.race;
        let c2_race = castle_data2.race;

        let has;
        if (c1_race == c2_race) {
            has = false;
        } else if (c1_race < c2_race) {
            has = (c2_race - c1_race) == 1;
        } else {
            has = (c1_race - c2_race) == 4;
        };
        has
    }

    /// Settle battle
    public fun battle_settlement_save_castle_data(game_store: &mut GameStore, mut castle_data: CastleData, win: bool, cooldown: u64, economic_base_power: u64, current_timestamp: u64, economy_buff_end: u64, soldiers_left: u64, exp_gain: u64) {
        // The function is used to update the state of the castle data after a battle

        /*
            game_store -> This is used to add castle_data to the game_store via a dynamic field
            castle_data -> the mutable castle_data object. This is the main focus point of this function, we need to update the castle_data after the battle
            win -> boolean that describes if the castle won or lost
            cooldown -> represents the battle cooldown (game design to make sure castles can't keep attacking each other)
            current_timestamp -> time stamp of the battle (it's going to be used to set the buff/debuff timer)
            economy_buff_end -> time when the econ buff/debuff will end
            soldiers_left -> how many soldiers are left after the battle
            exp_gain -> how much xp (if any) the castle will get
        */

        // 1. battle cooldown
        castle_data.millitary.battle_cooldown = cooldown; // set the battle_cooldown
        // 2. soldier left
        castle_data.millitary.soldiers = soldiers_left; // set the soldiers_left
        castle_data.economy.soldier_buff.power = calculate_soldiers_economic_power(soldiers_left); // calculate the new soldier econ power based on the soldiers left and sets it
        castle_data.economy.soldier_buff.start = current_timestamp; // sets when the buff/debuff will start
        // 3. soldiers caused total attack/defense power
        castle_data.millitary.total_attack_power = get_castle_total_attack_power(&castle_data); // sets total attack power for the castle
        castle_data.millitary.total_defense_power = get_castle_total_defense_power(&castle_data); // sets total defense power for the castle
        // 4. exp gain
        castle_data.experience_pool = castle_data.experience_pool + exp_gain; // sets the xp gain (could be zero by design for the losing castle)
        // 5. economy buff
        vector::push_back(&mut castle_data.economy.battle_buff, EconomicBuff {  // creates a new EconomicBuff object and adds it to the back of the Vector
            debuff: !win, // This is a logical NOT, if win is true it will set debuff to FALSE, if win is false it will set debuff to TRUE
            power: economic_base_power, // sets the economic_base_power for the buff/debuff
            start: current_timestamp, // sets the start of the buff
            end: economy_buff_end, // sets the end of the buff
        });
        // 6. put back to table
        dynamic_field::add(&mut game_store.id, castle_data.id, castle_data); // adds the castle_data to the game_store via dynamic field
    }


    /// Consume experience points from the experience pool to upgrade the castle
    public fun upgrade_castle(id: ID, game_store: &mut GameStore) { // ths function takes a castle id and mutable game_store to uprade your castle if you have the xp
        // 1. fetch castle data
        let castle_data = dynamic_field::borrow_mut<ID, CastleData>(&mut game_store.id, id); // gets the castle data via a mutable borrow (so we can make changes)

        // 2. continually upgrade if exp is enough
        let initial_level = castle_data.level;// set the initial level to the current level
        while (castle_data.level < MAX_CASTLE_LEVEL) { // loop while the castle data level is less than the MAX_CASTLE_LEVEL
            let exp_required_at_current_level = *vector::borrow(&REQUIRED_EXP_LEVELS, castle_data.level - 1); // gets the xp required for the level
            /*
                vector::borrow =  borrows an immutable reference from an array at index i

                REQUIRED_EXP_LEVELS -> this is a vector with all the xp required at each level so level1 = 100, level2 = 150 etc etc
                castle_data.level - 1 -> we do this because an array is zero indexed so to get level1, we need position 0 in the array (i.e. the first element) as an example
            */

            if(castle_data.experience_pool < exp_required_at_current_level) { // if the castle does not have enough xp to upgrade, break out of the loop
                break // keyword used to break out of loops
            };

            castle_data.experience_pool = castle_data.experience_pool - exp_required_at_current_level; // update the state of the xp as we just used some xp to upgrade
            castle_data.level = castle_data.level + 1; // levels up the castle
        };

        // 3. update powers if upgraded - if the castle was levelled up we need to update it's econ and defense power
        if (castle_data.level > initial_level) { // if the castle was levelled up
            let base_economic_power = calculate_castle_base_economic_power(freeze(castle_data)); // calculate the new base econ power based on the new level
            // note that we freeze the object because `calculate_castle_base_economic_power` only takes a reference to castle_data (we can't send it a mutable reference)
            castle_data.economy.base_power = base_economic_power; // set the updated econ power

            let (attack_power, defense_power) = calculate_castle_base_attack_defense_power(freeze(castle_data)); // calculate the new base military power based on the new level
            // note that we freeze the object because `calculate_castle_base_attack_defense_power` only takes a reference to castle_data (we can't send it a mutable reference)
            castle_data.millitary.attack_power = attack_power; // set the updated attack_power
            castle_data.millitary.defense_power = defense_power; // set the updated defense_power
        }
    }

    /// Calculate castle's base economic power
    fun calculate_castle_base_economic_power(castle_data: &CastleData): u64 { // calculates the initial castle base econ power referencing CastleData
        let initial_base_power = get_initial_economic_power(castle_data.size); // get initial power from size
        let level = castle_data.level; // get castle level
        math::divide_and_round_up(initial_base_power * 12 * math::pow(10, ((level - 1) as u8)), 10) // see the `calculate_castle_base_attack_defense_power` it works on the same principle
    }

    /// Get castle size factor
    fun get_castle_size_factor(castle_size: u64): u64 { // gets the castle factor by size. The factor is used to calculate the castle base attack and defense power
        let factor; // create variable
        if (castle_size == CASTLE_SIZE_SMALL) { // if the castle is small
            factor = CASTLE_SIZE_FACTOR_SMALL; // get the small factor
        } else if (castle_size == CASTLE_SIZE_MIDDLE) { // if the castle is medium
            factor = CASTLE_SIZE_FACTOR_MIDDLE; // get the medium factor
        } else if (castle_size == CASTLE_SIZE_BIG) { // if the castle is big
            factor = CASTLE_SIZE_FACTOR_BIG; // get the big factor
        } else {
            abort 0 // terminate the transaction
        };
        factor // return the factor
    }

    /// Calculate castle's base attack power and base defense power based on level
    /// base attack power = (castle_size_factor * initial_attack_power * (1.2 ^ (level - 1)))
    /// base defense power = (castle_size_factor * initial_defense_power * (1.2 ^ (level - 1)))
    fun calculate_castle_base_attack_defense_power(castle_data: &CastleData): (u64, u64) { // parameter is a reference to castleData (not mutable, thus not state changing)
        let castle_size_factor = get_castle_size_factor(castle_data.size); // get the castle size factor based on the size
        let (initial_attack, initial_defense) = get_initial_attack_defense_power(castle_data.race); // get the initial attack & defense power based on the race
        let attack_power = math::divide_and_round_up(castle_size_factor * initial_attack * 12 * math::pow(10, ((castle_data.level - 1) as u8)), 10);
        let defense_power = math::divide_and_round_up(castle_size_factor * initial_defense * 12 * math::pow(10, ((castle_data.level - 1) as u8)), 10);

        /*
            ok so there are 2 functions from the math module here `divide_and_round_up` and `pow` let's figure out what they do first

            divide_and_round_up: this function divides two variables x & y, BUT if there is a remainder it'll round up
            so if 10/5 = 2
            but 10/4 = 3

            pow: takes a base value and raises it to a power
            so if base x = 2
            power y = 2
            result = 4

            since `divide_and_round_up` is the outer function:
            x = castle_size_factor * initial_attack * 12 * math::pow(10, ((castle_data.level - 1) as u8))
            y = 10

            let's break x into pieces:
            piece a -> castle_size_factor * initial_attack * 12
            *
            piece b -> math::pow(10, ((castle_data.level - 1) as u8))

            piece a * piece b = piece c

            then finally:
            attack_power = divide_and_round_up(piece c, 10)
            defense_power = divide_and_round_up(piece c, 10)


            With numbers for a middle castle, race elf:
            castle_size_factor = 3
            initial_attack = 500
            initial_defense = 1500
            level = 1

            attack_power = divide_and_round_up(x:(3 * 500 * 12 * (10^0)), y: 10)
            attack_power = divide_and_round_up(18000/10)
            attack_power = 1800

            defense_power = divide_and_round_up(x:(3 * 1500 * 12 * (10^0)), y:10)
            defense_power = divide_and_round_up(54000/10)
            defense_power = 5400

         */

        (attack_power, defense_power) // return attack and defense power
    }

    /// 定义错误类型
    /// 战士数量超过限制
    const ESoldierCountLimit: u64 = 0;
    /// 招募战士资金不足
    const EInsufficientTreasury: u64 = 1;
    /// 没有足够的城堡参加战斗
    const ENotEnoughCastles: u64 = 2;

    /// 定义种族
    /// 城堡种族 - 人类
    const CASTLE_RACE_HUMAN : u64 = 0;
    /// 城堡种族 - 精灵
    const CASTLE_RACE_ELF : u64 = 1;
    /// 城堡种族 - 兽人
    const CASTLE_RACE_ORCS : u64 = 2;
    /// 城堡种族 - 妖族
    const CASTLE_RACE_GOBLIN : u64 = 3;
    /// 城堡种族 - 僵尸
    const CASTLE_RACE_UNDEAD : u64 = 4;


    /// 定义不同种族初始攻击力
    /// 人类初始攻击力
    const INITIAL_ATTCK_POWER_HUMAN : u64 = 1000;
    /// 精灵初始攻击力
    const INITIAL_ATTCK_POWER_ELF : u64 = 500;
    /// 兽人初始攻击力
    const INITIAL_ATTCK_POWER_ORCS : u64 = 1500;
    /// 妖族初始攻击力
    const INITIAL_ATTCK_POWER_GOBLIN : u64 = 1200;
    /// 僵尸初始攻击力
    const INITIAL_ATTCK_POWER_UNDEAD : u64 = 800;

    /// 定义不同种族初始防守力
    /// 人类初始防卫力
    const INITIAL_DEFENSE_POWER_HUMAN : u64 = 1000;
    /// 精灵初始防卫力
    const INITIAL_DEFENSE_POWER_ELF : u64 = 1500;
    /// 兽人初始防卫力
    const INITIAL_DEFENSE_POWER_ORCS : u64 = 500;
    /// 妖族初始防卫力
    const INITIAL_DEFENSE_POWER_GOBLIN : u64 = 800;
    /// 僵尸初始防卫力
    const INITIAL_DEFENSE_POWER_UNDEAD : u64 = 1200;

    /// 定义城堡尺寸
    /// 小型城堡
    const CASTLE_SIZE_SMALL : u64 = 1;
    /// 中型城堡
    const CASTLE_SIZE_MIDDLE : u64 = 2;
    /// 大型城堡
    const CASTLE_SIZE_BIG : u64 = 3;

    /// 定义经济能力
    /// 小城堡初始经济能力
    const INITIAL_ECONOMIC_POWER_SMALL_CASTLE : u64 = 100;
    /// 中城堡初始经济能力
    const INITIAL_ECONOMIC_POWER_MIDDLE_CASTLE : u64 = 150;
    /// 大城堡初始经济能力
    const INITIAL_ECONOMIC_POWER_BIG_CASTLE : u64 = 250;

    /// 初始士兵数量
    const INITIAL_SOLDIERS : u64 = 10;
    /// 士兵经济力量
    const SOLDIER_ECONOMIC_POWER : u64 = 1;
    /// 每一个士兵的价格
    const SOLDIER_PRICE : u64 = 100;



    /// Max soldier count per castle - small castle
    const MAX_SOLDIERS_SMALL_CASTLE : u64 = 500;
    /// Max soldier count per castle - middle castle
    const MAX_SOLDIERS_MIDDLE_CASTLE : u64 = 1000;
    /// Max soldier count per castle - big castle
    const MAX_SOLDIERS_BIG_CASTLE : u64 = 2000;

    /// Soldier attack power - human
    const SOLDIER_ATTACK_POWER_HUMAN : u64 = 100;
    /// Soldier defense power - human
    const SOLDIER_DEFENSE_POWER_HUMAN : u64 = 100;
    /// Soldier attack power - elf
    const SOLDIER_ATTACK_POWER_ELF : u64 = 50;
    /// Soldier defense power - elf
    const SOLDIER_DEFENSE_POWER_ELF : u64 = 150;
    /// Soldier attack power - orcs
    const SOLDIER_ATTACK_POWER_ORCS : u64 = 150;
    /// Soldier defense power - orcs
    const SOLDIER_DEFENSE_POWER_ORCS : u64 = 50;
    /// Soldier attack power - goblin
    const SOLDIER_ATTACK_POWER_GOBLIN : u64 = 120;
    /// Soldier defense power - goblin
    const SOLDIER_DEFENSE_POWER_GOBLIN : u64 = 80;
    /// Soldier attack power - undead
    const SOLDIER_ATTACK_POWER_UNDEAD : u64 = 120;
    /// Soldier defense power - undead
    const SOLDIER_DEFENSE_POWER_UNDEAD : u64 = 80;

    /// Experience points the winner gain in a battle based on winner's level 1 - 10
    const BATTLE_EXP_GAIN_LEVELS : vector<u64> = vector[25, 30, 40, 55, 75, 100, 130, 165, 205, 250];
    /// Experience points required for castle level 2 - 10
    const REQUIRED_EXP_LEVELS : vector<u64> = vector[100, 150, 225, 338, 507, 760, 1140, 1709, 2563];

    /// Max castle level
    const MAX_CASTLE_LEVEL : u64 = 10;

    /// Castle size factor - small
    const CASTLE_SIZE_FACTOR_SMALL : u64 = 2;
    /// Castle size factor - middle
    const CASTLE_SIZE_FACTOR_MIDDLE : u64 = 3;
    /// Castle size factor - big
    const CASTLE_SIZE_FACTOR_BIG : u64 = 5;

    /// Castle amount limit - small
    const CASTLE_AMOUNT_LIMIT_SMALL : u64 = 500;
    /// Castle amount limit - middle
    const CASTLE_AMOUNT_LIMIT_MIDDLE : u64 = 300;
    /// Castle amount limit - big
    const CASTLE_AMOUNT_LIMIT_BIG : u64 = 200;
}