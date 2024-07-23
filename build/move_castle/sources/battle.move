module move_castle::battle {
    use sui::clock::{Self, Clock};
    use sui::math;
    use sui::event;
    use move_castle::castle::Castle;
    use move_castle::core::{Self, GameStore};
    use std::u64;

    /// One or both sides of the battle are in battle cooldown
    const EBattleCooldown: u64 = 0;

    /// constant that represents the battle cooldown for the winner: 30s
    const BATTLE_WINNER_COOLDOWN_MS : u64 = 30 * 1000;
    /// constant that represents the loser's econ penalty:2 min
    const BATTLE_LOSER_ECONOMIC_PENALTY_TIME : u64 = 2 * 60 * 1000;
    /// constant that represents the loser cooldown: 2min
    const BATTLE_LOSER_COOLDOWN_MS : u64 = 2 * 60 * 1000;


    /// 战斗事件
    public struct CastleBattleLog has store, copy, drop {
        attacker: ID, /// 攻击者的id
        winner: ID, /// 胜利者是谁
        loser: ID, /// 失败者是谁
        winner_soldiers_lost: u64, /// 赢家损失的战士数量
        loser_soldiers_lost: u64,  /// 输家损失的战士数量
        reparation_economic_power: u64,  // this tells us what value of economic buff and debuff will be applied
        battle_time: u64, /// 战斗发生的时间
        reparation_end_time: u64  /// 增益到期的时间
    }


    entry fun battle(castle: &Castle, clock: &Clock, game_store: &mut GameStore, ctx: &mut TxContext) {
        /// 1. 随机选择一个目标
        let attacker_id = object::id(castle);
        let target_id = core::random_battle_target(attacker_id, game_store, ctx);

        /// 2. 获取城堡数据
        let (attacker, defender) = core::fetch_castle_data(attacker_id, target_id, game_store);

        /// 3. 检查战斗冷却
        let current_timestamp = clock::timestamp_ms(clock);
        /// 获取攻击者是否到了战斗冷却时间
        assert!(core::get_castle_battle_cooldown(&attacker) < current_timestamp, EBattleCooldown);
        /// 获取防卫者是否到了战斗冷却时间
        assert!(core::get_castle_battle_cooldown(&defender) < current_timestamp, EBattleCooldown);

        /// 4. 战斗
        /// 4.1 计算总的攻击力和防御力
        let mut attack_power = core::get_castle_total_attack_power(&attacker);
        let mut defense_power = core::get_castle_total_defense_power(&defender);

        /// 检查进行攻击种族是否有利
        if (core::has_race_advantage(&attacker, &defender)) {
            /// 攻击种族如果有利，添加50%攻击收益
            attack_power = u64::divide_and_round_up(attack_power * 15, 10);
        } else if (core::has_race_advantage(&defender, &attacker)) { /// 检查进行防守种族是否有利
            /// 攻击种族如果有利，添加50%防守收益
            defense_power = u64::divide_and_round_up(defense_power * 15, 10)
        };

        /// 4.2 决定输赢
        let (mut winner, mut loser);
        /// 攻击收益如果大于防守收益，攻击者救赎赢家，防守者就是输家；否则，反之
        if (attack_power > defense_power) {
            winner = attacker;
            loser = defender;
        } else {
            winner = defender;
            loser = attacker;
        };
        /// 获取赢家和输家的城堡的id
        let winner_id = core::get_castle_id(&winner);
        let loser_id = core::get_castle_id(&loser);

        /// 5. 战斗结算
        /// 5.1 结算赢家
        core::settle_castle_economy_inner(clock, &mut winner);

        /// 获取赢家和输家城堡的总士兵防御力
        let winner_solders_total_defense_power = core::get_castle_total_soldiers_defense_power(&winner);
        let loser_solders_total_attack_power = core::get_castle_total_soldiers_defense_power(&loser);

        /// 赢家剩余多少战士
        let winner_soldiers_left;
        /// 如果赢家战士防御力值 大于 输家战士防御力值
        if (winner_solders_total_defense_power > loser_solders_total_attack_power) {
            /// 获取赢家种族，然后根据种族获取该城堡战士攻击和防御力值
            let (_, winner_soldier_defense_power) = core::get_castle_soldier_attack_defense_power(core::get_castle_race(&winner)); // takes the winner's race and gets the defense power of a SINGLE soldier
            /// (赢家战士总防御力值 - 输家战士总攻击力值) /赢家战士防御力 = 赢家剩余的战士数量
            /// 1500 - 500 = 1000
            /// 1000 / 100 = 10
            /// 10 soldiers are left
            winner_soldiers_left = u64::divide_and_round_up(winner_solders_total_defense_power - loser_solders_total_attack_power, winner_soldier_defense_power);
        } else {
            winner_soldiers_left = 0;
        };

        let winner_soldiers_lost = core::get_castle_soldiers(&winner) - winner_soldiers_left; // new variable to determine how many soldiers were lost
        let winner_exp_gain = core::battle_winner_exp(&winner); // get exp for the win
        let reparation_economic_power = core::get_castle_economic_base_power(&loser); // get the loser's econ power to add as a buff to the winner
        core::battle_settlement_save_castle_data(
            game_store, // game store state for the dynamic field update
            winner, // winner castle id
            true, // true means it's a win
            current_timestamp + BATTLE_WINNER_COOLDOWN_MS, // updates the cooldown
            reparation_economic_power, // updates the new econ power
            current_timestamp, // time battle took place
            current_timestamp + BATTLE_LOSER_ECONOMIC_PENALTY_TIME, // battle time + econ buff
            winner_soldiers_left, // updates winner soldiers left
            winner_exp_gain // xp gain for the win
        );

        // 5.2 settling loser
        core::settle_castle_economy_inner(clock, &mut loser); // settles the loser economy
        let loser_soldiers_left = 0; // sets soldiers left to zero
        let loser_soldiers_lost = core::get_castle_soldiers(&loser) - loser_soldiers_left; // no reson to add loser_soldiers_left here since it'll always be zero
        core::battle_settlement_save_castle_data( // updates the data for the castle
            game_store, // game store state for the dynamic field update
            loser, // loser castle id
            false, // false means it's not a win
            current_timestamp + BATTLE_LOSER_COOLDOWN_MS, // updates the cooldown
            reparation_economic_power, // updates the new econ power
            current_timestamp, // time battle took place
            current_timestamp + BATTLE_LOSER_ECONOMIC_PENALTY_TIME, // battle time + time penalty
            loser_soldiers_left, // will always be zero becuase of the loss
            0 // no xp gain
        );

        // 6. emit event
        event::emit(CastleBattleLog { // log the battle
            attacker: attacker_id, // attacker id
            winner: winner_id, // winner id
            loser: loser_id,// loser id
            winner_soldiers_lost: winner_soldiers_lost, // how many soldiers did the winner lose?
            loser_soldiers_lost: loser_soldiers_lost, // how many soldiers did the loser lose?
            reparation_economic_power: reparation_economic_power, // this tells us what value of economic buff and debuff will be applied
            battle_time: current_timestamp, // time the battle happened
            reparation_end_time: current_timestamp + BATTLE_LOSER_ECONOMIC_PENALTY_TIME // end time for negative or positive affect
        });

    }

}
