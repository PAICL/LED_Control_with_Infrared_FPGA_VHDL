-- 红外接收解码模块
-- 功能：解码红外信号（NEC协议等），提取数据位并检测重复帧
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY infrared_rcv IS
    PORT (
        sys_clk : IN STD_LOGIC; -- 系统时钟（假设为50MHz）
        sys_rst_n : IN STD_LOGIC; -- 异步复位，低有效
        infrared_in : IN STD_LOGIC; -- 红外输入信号（低电平表示有载波）
        repeat_en : OUT STD_LOGIC; -- 重复帧标志（高电平表示重复帧）
        data : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- 解码后的数据（命令码）
        data_enable : OUT STD_LOGIC -- 数据有效标志（新增）
    );
END infrared_rcv;

ARCHITECTURE behavioral OF infrared_rcv IS
    -- 时间常数定义（基于50MHz时钟周期20ns计算）
    CONSTANT CNT_0_56MS_L : INTEGER := 20000; -- 0.56ms低阈值 (0.56ms / 20ns = 28,000，可能与实际协议调整有关)
    CONSTANT CNT_0_56MS_H : INTEGER := 35000; -- 0.56ms高阈值
    CONSTANT CNT_1_69MS_L : INTEGER := 80000; -- 1.69ms低阈值
    CONSTANT CNT_1_69MS_H : INTEGER := 90000; -- 1.69ms高阈值
    CONSTANT CNT_2_25MS_L : INTEGER := 100000; -- 2.25ms低阈值
    CONSTANT CNT_2_25MS_H : INTEGER := 125000; -- 2.25ms高阈值
    CONSTANT CNT_4_5MS_L : INTEGER := 175000; -- 4.5ms低阈值
    CONSTANT CNT_4_5MS_H : INTEGER := 275000; -- 4.5ms高阈值
    CONSTANT CNT_9MS_L : INTEGER := 400000; -- 9ms低阈值（实际=400000*20ns=8ms，可能与协议调整有关）
    CONSTANT CNT_9MS_H : INTEGER := 490000; -- 9ms高阈值
    CONSTANT CNT_10MS : INTEGER := 500000; -- 10ms计数值（新增） 1ms

    -- 状态机状态定义
    TYPE state_type IS (
        IDLE, -- 空闲状态，等待起始下降沿
        S_T9, -- 检测起始9ms低电平脉冲
        S_JUDGE, -- 判断是否为重复帧或数据帧
        S_IFR_DATA, -- 接收数据位（32位：地址、地址反码、命令、命令反码）
        S_REPEAT -- 重复帧处理
    );

    -- 内部信号声明
    SIGNAL infrared_in_d1 : STD_LOGIC; -- 输入延迟1拍，用于边沿检测
    SIGNAL infrared_in_d2 : STD_LOGIC; -- 输入延迟2拍
    SIGNAL cnt : unsigned(18 DOWNTO 0); -- 通用计数器（最大计数2^19=524,288）
    SIGNAL flag_0_56ms : STD_LOGIC; -- 0.56ms标志（用于逻辑0识别）
    SIGNAL flag_1_69ms : STD_LOGIC; -- 1.69ms标志（用于逻辑1识别）
    SIGNAL flag_2_25ms : STD_LOGIC; -- 2.25ms标志（重复帧间隔）
    SIGNAL flag_4_5ms : STD_LOGIC; -- 4.5ms标志（数据帧间隔）
    SIGNAL flag_9ms : STD_LOGIC; -- 9ms标志（起始脉冲）
    SIGNAL state : state_type; -- 状态机当前状态
    SIGNAL data_cnt : unsigned(5 DOWNTO 0); -- 数据位计数器（0~31）
    SIGNAL data_tmp : STD_LOGIC_VECTOR(31 DOWNTO 0); -- 临时存储32位接收数据

    -- 新增信号：数据保持控制
    SIGNAL data_reg : STD_LOGIC_VECTOR(7 DOWNTO 0); -- 数据锁存寄存器
    SIGNAL data_valid : STD_LOGIC; -- 数据有效标志
    SIGNAL cnt_hold : unsigned(19 DOWNTO 0); -- 10ms计数器（2^20=1,048,576 > 500,000）

    -- 边沿检测信号
    SIGNAL ifr_in_rise : STD_LOGIC; -- 上升沿检测（infrared_in_d1上升沿）
    SIGNAL ifr_in_fall : STD_LOGIC; -- 下降沿检测（infrared_in_d1下降沿）

BEGIN
    -- 边沿检测组合逻辑
    ifr_in_rise <= NOT infrared_in_d2 AND infrared_in_d1; -- 检测上升沿
    ifr_in_fall <= infrared_in_d2 AND NOT infrared_in_d1; -- 检测下降沿

    -- 输入延迟进程（同步化与边沿检测）
    PROCESS (sys_clk, sys_rst_n)
    BEGIN
        IF sys_rst_n = '0' THEN
            infrared_in_d1 <= '0';
            infrared_in_d2 <= '0';
        ELSIF rising_edge(sys_clk) THEN
            infrared_in_d1 <= infrared_in; -- 延迟1拍
            infrared_in_d2 <= infrared_in_d1; -- 延迟2拍
        END IF;
    END PROCESS;

    -- 计数器控制进程（根据状态管理计数器）
    PROCESS (sys_clk, sys_rst_n)
    BEGIN
        IF sys_rst_n = '0' THEN
            cnt <= (OTHERS => '0');
        ELSIF rising_edge(sys_clk) THEN
            CASE state IS
                WHEN IDLE =>
                    cnt <= (OTHERS => '0'); -- 空闲时计数器清零
                WHEN S_T9 =>
                    -- 检测到上升沿且9ms标志有效时清零，否则递增
                    IF ifr_in_rise = '1' AND flag_9ms = '1' THEN
                        cnt <= (OTHERS => '0');
                    ELSE
                        cnt <= cnt + 1;
                    END IF;
                WHEN S_JUDGE =>
                    -- 检测到下降沿且满足时间条件时清零，否则递增
                    IF ifr_in_fall = '1' AND (flag_2_25ms = '1' OR flag_4_5ms = '1') THEN
                        cnt <= (OTHERS => '0');
                    ELSE
                        cnt <= cnt + 1;
                    END IF;
                WHEN S_IFR_DATA =>
                    -- 在数据位接收过程中，根据边沿和标志位清零计数器
                    IF (flag_0_56ms = '1' AND ifr_in_rise = '1') OR
                        ((flag_0_56ms = '1' OR flag_1_69ms = '1') AND ifr_in_fall = '1') THEN
                        cnt <= (OTHERS => '0');
                    ELSE
                        cnt <= cnt + 1;
                    END IF;
                WHEN OTHERS =>
                    cnt <= (OTHERS => '0');
            END CASE;
        END IF;
    END PROCESS;

    -- 0.56ms标志生成（逻辑0对应的高电平时间）
    PROCESS (sys_clk, sys_rst_n)
    BEGIN
        IF sys_rst_n = '0' THEN
            flag_0_56ms <= '0';
        ELSIF rising_edge(sys_clk) THEN
            -- 在数据接收状态，若计数器在0.56ms范围内则置位
            IF state = S_IFR_DATA AND cnt >= CNT_0_56MS_L AND cnt <= CNT_0_56MS_H THEN
                flag_0_56ms <= '1';
            ELSE
                flag_0_56ms <= '0';
            END IF;
        END IF;
    END PROCESS;

    -- flag_1_69ms：1.69ms标志（逻辑1对应的高电平时间）
    PROCESS (sys_clk, sys_rst_n)
    BEGIN
        IF sys_rst_n = '0' THEN
            flag_1_69ms <= '0';
        ELSIF rising_edge(sys_clk) THEN
            IF state = S_IFR_DATA AND cnt >= CNT_1_69MS_L AND cnt <= CNT_1_69MS_H THEN
                flag_1_69ms <= '1';
            ELSE
                flag_1_69ms <= '0';
            END IF;
        END IF;
    END PROCESS;

    -- flag_2_25ms：2.25ms标志（重复帧间隔时间）
    PROCESS (sys_clk, sys_rst_n)
    BEGIN
        IF sys_rst_n = '0' THEN
            flag_2_25ms <= '0';
        ELSIF rising_edge(sys_clk) THEN
            IF state = S_JUDGE AND cnt >= CNT_2_25MS_L AND cnt <= CNT_2_25MS_H THEN
                flag_2_25ms <= '1';
            ELSE
                flag_2_25ms <= '0';
            END IF;
        END IF;
    END PROCESS;

    -- flag_4_5ms：4.5ms标志（数据帧引导时间）
    PROCESS (sys_clk, sys_rst_n)
    BEGIN
        IF sys_rst_n = '0' THEN
            flag_4_5ms <= '0';
        ELSIF rising_edge(sys_clk) THEN
            IF state = S_JUDGE AND cnt >= CNT_4_5MS_L AND cnt <= CNT_4_5MS_H THEN
                flag_4_5ms <= '1';
            ELSE
                flag_4_5ms <= '0';
            END IF;
        END IF;
    END PROCESS;

    -- flag_9ms：9ms标志（起始脉冲低电平时间）
    PROCESS (sys_clk, sys_rst_n)
    BEGIN
        IF sys_rst_n = '0' THEN
            flag_9ms <= '0';
        ELSIF rising_edge(sys_clk) THEN
            IF state = S_T9 AND cnt >= CNT_9MS_L AND cnt <= CNT_9MS_H THEN
                flag_9ms <= '1';
            ELSE
                flag_9ms <= '0';
            END IF;
        END IF;
    END PROCESS;

    -- 状态机主控进程
    PROCESS (sys_clk, sys_rst_n)
    BEGIN
        IF sys_rst_n = '0' THEN
            state <= IDLE;
        ELSIF rising_edge(sys_clk) THEN
            CASE state IS
                WHEN IDLE =>
                    -- 检测到下降沿（起始信号）进入S_T9状态
                    IF ifr_in_fall = '1' THEN
                        state <= S_T9;
                    END IF;
                WHEN S_T9 =>
                    -- 检测到上升沿后，检查是否满足9ms标志
                    IF ifr_in_rise = '1' THEN
                        IF flag_9ms = '1' THEN -- 有效起始脉冲
                            state <= S_JUDGE;
                        ELSE -- 无效脉冲，返回空闲
                            state <= IDLE;
                        END IF;
                    END IF;
                WHEN S_JUDGE =>
                    -- 检测到下降沿后判断是重复帧还是数据帧
                    IF ifr_in_fall = '1' THEN
                        IF flag_2_25ms = '1' THEN -- 重复帧间隔时间
                            state <= S_REPEAT;
                        ELSIF flag_4_5ms = '1' THEN -- 数据帧间隔时间
                            state <= S_IFR_DATA;
                        ELSE -- 无效，返回空闲
                            state <= IDLE;
                        END IF;
                    END IF;
                WHEN S_IFR_DATA =>
                    -- 数据接收完成或错误时返回空闲
                    IF (ifr_in_rise = '1' AND data_cnt = 32) OR -- 正常接收完成
                        (ifr_in_rise = '1' AND flag_0_56ms = '0') OR -- 时间不符
                        (ifr_in_fall = '1' AND flag_0_56ms = '0' AND flag_1_69ms = '0') THEN -- 错误
                        state <= IDLE;
                    END IF;
                WHEN S_REPEAT =>
                    -- 重复帧处理，上升沿后返回空闲
                    IF ifr_in_rise = '1' THEN
                        state <= IDLE;
                    END IF;
                WHEN OTHERS =>
                    state <= IDLE;
            END CASE;
        END IF;
    END PROCESS;

    -- 数据临时寄存器存储（32位数据：地址+地址反码+命令+命令反码）
    PROCESS (sys_clk, sys_rst_n)
    BEGIN
        IF sys_rst_n = '0' THEN
            data_tmp <= (OTHERS => '0');
        ELSIF rising_edge(sys_clk) THEN
            -- 在数据接收状态的下升沿（高电平结束）存储数据位
            IF state = S_IFR_DATA AND ifr_in_fall = '1' THEN
                -- 根据高电平持续时间判断逻辑值
                IF flag_0_56ms = '1' THEN -- 逻辑0
                    data_tmp(to_integer(data_cnt)) <= '0';
                ELSIF flag_1_69ms = '1' THEN -- 逻辑1
                    data_tmp(to_integer(data_cnt)) <= '1';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    -- 数据位计数器控制
    PROCESS (sys_clk, sys_rst_n)
    BEGIN
        IF sys_rst_n = '0' THEN
            data_cnt <= (OTHERS => '0');
        ELSIF rising_edge(sys_clk) THEN
            -- 完成32位接收后清零，或在数据位下降沿递增
            IF ifr_in_rise = '1' AND data_cnt = 32 THEN
                data_cnt <= (OTHERS => '0');
            ELSIF ifr_in_fall = '1' AND state = S_IFR_DATA THEN
                data_cnt <= data_cnt + 1;
            END IF;
        END IF;
    END PROCESS;

    -- 重复帧使能输出逻辑
    PROCESS (sys_clk, sys_rst_n)
    BEGIN
        IF sys_rst_n = '0' THEN
            repeat_en <= '0';
        ELSIF rising_edge(sys_clk) THEN
            -- 在重复帧状态且地址反码校验正确时置位
            IF state = S_REPEAT AND data_tmp(23 DOWNTO 16) = NOT data_tmp(31 DOWNTO 24) THEN
                repeat_en <= '1';
            ELSE
                repeat_en <= '0';
            END IF;
        END IF;
    END PROCESS;

    -- 数据输出逻辑（命令码为data_tmp[23:16]）
    --PROCESS (sys_clk, sys_rst_n)
    --BEGIN
    --    IF sys_rst_n = '0' THEN
    --        data <= (OTHERS => '0');
    --    ELSIF rising_edge(sys_clk) THEN
    --        -- 直接输出命令码部分
    --        data <= data_tmp(23 DOWNTO 16);
    --        -- 完整校验（可选，但代码中注释部分未启用）
    --        -- 当32位数据接收完成且反码校验正确时更新输出
    --        IF data_tmp(23 DOWNTO 16) = NOT data_tmp(31 DOWNTO 24) AND
    --            data_tmp(7 DOWNTO 0) = NOT data_tmp(15 DOWNTO 8) AND
    --            data_cnt = 32 THEN
    --            -- 此处可添加数据有效性确认逻辑
    --            -- 当前设计直接持续输出命令码，依赖外部处理校验
    --        END IF;
    --    END IF;
    --END PROCESS;

    -- 数据锁存与保持控制（新增逻辑）
    PROCESS (sys_clk, sys_rst_n)
    BEGIN
        IF sys_rst_n = '0' THEN
            data_reg <= (OTHERS => '0');
            data_valid <= '0';
            cnt_hold <= (OTHERS => '0');
        ELSIF rising_edge(sys_clk) THEN
            -- 数据帧接收完成且校验通过
            IF state = S_IFR_DATA AND data_cnt = 32 AND
                data_tmp(23 DOWNTO 16) = NOT data_tmp(31 DOWNTO 24) --AND
                --data_tmp(7 DOWNTO 0) = NOT data_tmp(15 DOWNTO 8) 
                THEN
                data_reg <= data_tmp(23 DOWNTO 16); -- 锁存有效数据
                data_valid <= '1'; -- 置位有效标志
                cnt_hold <= (OTHERS => '0'); -- 重置保持计数器

                -- 重复帧处理
            ELSIF state = S_REPEAT AND data_tmp(23 DOWNTO 16) = NOT data_tmp(31 DOWNTO 24) THEN
                data_valid <= '1'; -- 刷新有效标志
                cnt_hold <= (OTHERS => '0'); -- 重置保持计数器
                -- data_reg 保持原值

                -- 保持计数器递增
            ELSIF data_valid = '1' THEN
                IF cnt_hold < CNT_10MS THEN
                    cnt_hold <= cnt_hold + 1;
                ELSE
                    data_valid <= '0'; -- 超时后清除有效标志
                    data_reg <= (OTHERS => '0'); -- 可选：清除数据（根据需求）
                END IF;
            END IF;
        END IF;
    END PROCESS;

    -- 输出连接
    data <= data_reg;
    data_enable <= data_valid;

END behavioral;