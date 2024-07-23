module move_castle::utils {
    use std::string::{Self, String};
    use std::hash;


    /// 产生城堡序列号
    public fun generate_castle_serial_number(size: u64, id: &mut UID): u64 {
        /// 通过uid转换成字节数组，然后通过sha2_256计算hashcode
        /// [25, 50, 75, 100, 125, 150, 175, 200]
        let mut hash = hash::sha2_256(object::uid_to_bytes(id)); // takes the object id as bytes and hashes it. This hash is a vector<u8>;

        let mut result_num: u64 = 0;

        /// 获取hash摘要的长度
        while (vector::length(&hash) > 0) {
            /// 从字节数组中取出第一个元素数据
            let element = vector::remove(&mut hash, 0); // takes an 'i' element out of the hash, we start with 0 (the first element)
            /// 第一轮循环: 0 | 25 = 00000 | 11001 = 11001 = 25
            /// 第二轮循环: 25 | 50 = 011001 | 110010 = 111011 = 59
            /// 第三轮循环: 59 | 75 = 0111011 | 1001011 = 1111011 = 123
            /// 以此类推，直到字节数组中最后一个数组参加完运算
            result_num = ((result_num << 8) | (element as u64));
            /// 这一轮结束后，继续遍历下一轮

        };

        /// 获取最后5位数
        /// 12345 % 10 = 1234.5 = 5
        /// 12345 % 100= 123.45 = 45
        result_num = result_num % 100000u64; // only get the last 5 digits

        size * 100000u64 + result_num
    }

    /// 根据序列号转化成image_id
    public fun serial_number_to_image_id(serial_number: u64): String { // takes a u64 serial number and returns a string. We use this to generate the images
        let id = serial_number / 10 % 10000u64;
        u64_to_string(id, 4) // cast the id to a string
    }

    /// 计算绝对值
    public fun abs_minus(a: u64, b: u64): u64 { // takes in 2 uints, returns a uint. This function returns the difference between two u64's
        let result;
        if (a > b) {
            result = a - b;
        } else {
            result = b - a;
        };
        result
    }

    /// 产生指定范围内的随机数
    public fun random_in_range(range: u64, ctx: &mut TxContext):u64 { // takes a range as uint and a TxContext. This function is very similar to `generate_castle_serial_number` but you can choose the range/size
        /// 创建一个uid
        let uid = object::new(ctx);
        /// 产生一个字节数组然后进行哈希，vector<u8>
        let mut hash = hash::sha2_256(object::uid_to_bytes(&uid)); // gets a sha256 hash of the object, this returns a vector<u8>;
        /// 删除这个uid
        object::delete(uid);

        let mut result_num: u64 = 0;
        while (vector::length(&hash) > 0) {
            /// 获取字节数组中第一个二进制code
            let element = vector::remove(&mut hash, 0);
            /// 进行或运算
            result_num = (result_num << 8) | (element as u64);
        };

        /// 计算得到的值 % 范围
        result_num = result_num % range;
        /// 返回这个值
        result_num
    }


    public fun u64_to_string(mut n: u64, fixed_length: u64): String { // takes a mutable uint + uint to represent length
        let mut result: vector<u8> = vector::empty<u8>();
        if (n == 0) {
            vector::push_back(&mut result, 48); /// 将0放到这个集合或者数组中返回，48的二进制表示就是0
        } else {
            /// 对于一个数据n=1345678, 通过%10得到余数，每次可以获取最后一位数字；通过/10，获取到商，这个商每次都可以去掉最后一位数字
            /// 1345678 % 10 = 8 1345678 / 10 = 134567
            /// 134567 % 10 = 7 134567 / 10 = 13456
            /// 13456 % 10 = 6 13456 / 10 = 1345
            /// 以此类推，直到n=0,就表示已经把整个数字遍历完成
            while (n > 0) {
                let digit = ((n % 10) as u8) + 48;
                vector::push_back(&mut result, digit);
                n = n / 10;
            };

            /// 如果长度不够，则用0填充，比如希望返回6位长度字符串，但是数字只有3位，比如123，这时候会将123 -> 123000
            while (vector::length(&result) < fixed_length) {
                vector::push_back(&mut result, 48);
            };
            /// 将数组反转
            vector::reverse<u8>(&mut result); // reverse the order of the elements 123000 -> 000321
        };
        string::utf8(result)
    }

}







