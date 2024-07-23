module move_castle::castle {
    use std::string::{Self, utf8, String};
    use sui::package;
    use sui::display;
    use sui::clock::{Self, Clock};
    use sui::event;
    use move_castle::utils;
    use move_castle::core::{Self, GameStore};

    /// 城堡数量达到限制
    const ECastleAmountLimit: u64 = 0;

    /// One-Time-Witness for the module
    public struct CASTLE has drop {}


    /// 城堡对象
    public struct Castle has key, store{ // this is the castle object. It has the key and store abilities which makes it an asset
        id: UID, /// 全局唯一ID
        name: String, /// 城堡名称
        description: String, /// 城堡描述
        serial_number: u64, /// 城堡序列号
        image_id: String, /// 城堡图片id
    }

    /// 构建城堡事件
    public struct CastleBuilt has copy, drop { // this struct is used as an event
        id: ID,
        owner: address, /// 城堡的所有者是谁
    }

    fun init(otw: CASTLE, ctx: &mut TxContext) {
        // the keys and values are for the display object
        let keys = vector[
            utf8(b"name"),
            utf8(b"link"),
            utf8(b"image_url"),
            utf8(b"description"),
            utf8(b"project_url"),
            utf8(b"creator"),
        ];

        let values = vector[
            utf8(b"{name}"), /// utf8 creates a new string from bytes `utf8(bytes: vector<u8>): String`. The b tells the move compiler we're dealing with bytes
            utf8(b"https://movecastle.info/castles/{serial_number}"), /// utf8 creates a new string from bytes `utf8(bytes: vector<u8>): String`. The b tells the move compiler we're dealing with bytes
            utf8(b"https://images.movecastle.info/static/media/castles/{image_id}.png"), /// utf8 creates a new string from bytes `utf8(bytes: vector<u8>): String`. The b tells the move compiler we're dealing with bytes
            utf8(b"{description}"), /// utf8 creates a new string from bytes `utf8(bytes: vector<u8>): String`. The b tells the move compiler we're dealing with bytes
            utf8(b"https://movecastle.info"), /// utf8 creates a new string from bytes `utf8(bytes: vector<u8>): String`. The b tells the move compiler we're dealing with bytes
            utf8(b"Castle Builder"), /// utf8 creates a new string from bytes `utf8(bytes: vector<u8>): String`. The b tells the move compiler we're dealing with bytes
        ];

        let publisher = package::claim(otw, ctx);
        /*
        The publisher object is explained here https://move-book.com/programmability/publisher.html
        It's used to prove authority. In this case the publisher is the sender i.e. the person
        who initiates the module. We're using the publisher for the display object below.

        Note this is the reason why we're using the OTW
        */

        let mut display = display::new_with_fields<Castle>(&publisher, keys, values, ctx);
        /* https://move-book.com/programmability/display.html

            The  display object exists to extend the object metadata for display purposes. It makes sense if you think about the fact
            that objects are owned by users, but the object display can be owned by the publisher. This means that the publisher can add
            metadata for objects on a global level
        */

        display::update_version(&mut display); // updates the version of the newly created object

        transfer::public_transfer(publisher, tx_context::sender(ctx)); // transfers the publisher object to the sender
        transfer::public_transfer(display, tx_context::sender(ctx)); // transfers the display object to the sender
    }

    /// 构建城堡
    entry fun build_castle(
            size: u64, /// 城堡规模
            name_bytes: vector<u8>, /// 城堡名字字节数组
            desc_bytes: vector<u8>, /// 城堡描述字节数组
            clock: &Clock, /// 时间操作组件
            game_store: &mut GameStore, /// 游戏存储
            ctx: &mut TxContext) {
        /// 是否允许继续构建城堡
        assert!(core::allow_new_castle(size, game_store), ECastleAmountLimit);

        /// 产生一个全局唯一id
        let mut obj_id = object::new(ctx);
        /// 产生一个序列号
        let serial_number = utils::generate_castle_serial_number(size, &mut obj_id);
        let image_id = utils::serial_number_to_image_id(serial_number);
        /// 创建一个Castle对象
        let castle = Castle {
            id: obj_id,
            name: string::utf8(name_bytes),
            description: string::utf8(desc_bytes),
            serial_number: serial_number,
            image_id: image_id
        };
        /// 从一个已有的对象中提取出来内部标识
        let id = object::uid_to_inner(&castle.id);
        let race = get_castle_race(serial_number);
        /// 初始化城堡数据
        core::init_castle_data(
            id,
            size,
            race,
            clock::timestamp_ms(clock),
            game_store
        );

        let owner = tx_context::sender(ctx);
        transfer::public_transfer(castle, owner);
        event::emit(CastleBuilt{id: id, owner: owner});
    }

    /// 转移城堡给其他地址
    entry fun transfer_castle(castle: Castle, to: address) {
        transfer::transfer(castle, to);
    }

    /// 结算城堡的经济
    entry fun settle_castle_economy(castle: &Castle, clock: &Clock, game_store: &mut GameStore) {
        core::settle_castle_economy(object::id(castle), clock, game_store);
    }

    /// 城堡使用金库招募士兵
    entry fun recruit_soldiers(castle: &Castle, count: u64, clock: &Clock, game_store: &mut GameStore) {
        core::recruit_soldiers(object::id(castle), count, clock, game_store);
    }

    /// 根据序列化获取种族
    public fun get_castle_race(serial_number: u64): u64 {
        /// 获取左后一个数字
        let mut race_number = serial_number % 10;
        /// 数字大于5, 就往下递减5, 得到一个小于5的数, 因为种族就是小于5
        if (race_number >= 5) {
            race_number = race_number - 5;
        };
        race_number
    }


    /// Upgrade castle
    entry fun upgrade_castle(castle: &mut Castle, game_store: &mut GameStore) {
        /*
        Calls the core module to upgrade the castle

        castle: &mut Castle -> mutable reference to the castle object
        game_store: &mut GameStore -> mutable reference to the GameStore
        */
        core::upgrade_castle(object::id(castle), game_store);
        // object::id(castle) -> gets the underlying ID of the castle
    }
}
