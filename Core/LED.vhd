LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY LED IS
    PORT (
        LED_RST : IN STD_LOGIC; -- 复位信号（高电平有效）
        LED_Enable : IN STD_LOGIC; -- 使能信号（1：工作 0：关闭）
        LED_CLK : IN STD_LOGIC; -- 主时钟（50MHz）
        clk_1ms : IN STD_LOGIC; -- 1ms时钟输入
        LED_Value : IN STD_LOGIC_VECTOR(9 DOWNTO 0); -- LED初始值（10位，对应10个LED）
        LED_BRIGHT : IN STD_LOGIC_VECTOR(3 DOWNTO 0); -- 亮度参数（0-15，0最暗，15最亮）
        LED_Direction : IN STD_LOGIC_VECTOR(1 DOWNTO 0); -- 方向控制（模式2有效："10"左移 "01"右移）
        LED_Speed : IN STD_LOGIC_VECTOR(3 DOWNTO 0); -- 速度控制（0-15，见下方说明）
        LED_Mode : IN STD_LOGIC_VECTOR(1 DOWNTO 0); -- 模式控制（0-1对应不同模式）
        LED_OUTPUT : OUT STD_LOGIC_VECTOR(9 DOWNTO 0) -- LED物理输出信号
    );
END LED;

ARCHITECTURE Behavioral OF LED IS
    -- 内部信号定义
    SIGNAL LED_Value_Seg : STD_LOGIC_VECTOR(9 DOWNTO 0) := (OTHERS => '0'); -- LED显示缓冲寄存器
    SIGNAL speed_counter : UNSIGNED(15 DOWNTO 0) := (OTHERS => '0'); -- 速度分频计数器
    SIGNAL speed_tick : STD_LOGIC := '0'; -- 速度触发脉冲
    SIGNAL blink_state : STD_LOGIC := '0'; -- 闪烁模式状态寄存器
    SIGNAL move_direction : STD_LOGIC := '0'; -- 移动方向缓存（0：右移 1：左移）

    -- PWM参数
    CONSTANT PWM_MAX : INTEGER := 15; -- PWM周期=16个时钟周期
    SIGNAL pwm_counter : INTEGER RANGE 0 TO PWM_MAX := 0; -- PWM周期计数器
    SIGNAL pwm_output_reg : STD_LOGIC_VECTOR(9 DOWNTO 0) := (OTHERS => '0'); -- PWM输出缓冲

    -- LED模式状态机
    TYPE led_state_mode_type IS (
        NO_LIGHT, -- 无灯状态
        FLOW_LIGHT, -- 正向流水灯
        BLINKING_LIGHT, -- 闪烁灯
        FULL_LIGHT         --全亮
    );

    -- LED控制信号
    SIGNAL led_state_mode : led_state_mode_type := NO_LIGHT;
    SIGNAL ms_counter : INTEGER RANGE 0 TO 499999999 := 0;
    SIGNAL flow_LED_reg : STD_LOGIC_VECTOR(9 DOWNTO 0) := "0000000001"; --流水灯位移寄存器
    SIGNAL LED_Mode_prev : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";--前一LED控制模式状态寄存
    SIGNAL LED_Speed_reg : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0001";

BEGIN
    --============================================================================--
    -- 基于1ms时钟的速度分频器
    -- 使用clk_1ms输入时钟，每个时钟周期为1ms
    --============================================================================--
    PROCESS (clk_1ms, LED_RST)
        VARIABLE speed_target : INTEGER := 0;
    BEGIN
        IF LED_RST = '0' THEN
            speed_counter <= (OTHERS => '0');
            speed_tick <= '0';
        ELSIF rising_edge(clk_1ms) THEN
            -- 根据速度等级设置目标计数值（单位：ms）
            CASE TO_INTEGER(UNSIGNED(LED_Speed)) IS
                WHEN 0 => speed_target := 0; -- 停止
                WHEN 1 => speed_target := 8000; -- 8s
                WHEN 2 => speed_target := 7000; -- 7s
                WHEN 3 => speed_target := 6000; -- 6s
                WHEN 4 => speed_target := 5000; -- 5s
                WHEN 5 => speed_target := 4000; -- 4s
                WHEN 6 => speed_target := 3000; -- 3s
                WHEN 7 => speed_target := 2000; -- 2s
                WHEN 8 => speed_target := 1000; -- 1s
                WHEN 9 => speed_target := 500; -- 0.5s
                WHEN 10 => speed_target := 333; -- 0.333s
                WHEN 11 => speed_target := 250; -- 0.25s
                WHEN 12 => speed_target := 200; -- 0.2s
                WHEN 13 => speed_target := 166; -- 0.166s
                WHEN 14 => speed_target := 142; -- 0.142s
                WHEN 15 => speed_target := 125; -- 0.125s
                WHEN OTHERS => speed_target := 1000;
            END CASE;

            IF speed_target = 0 THEN
                speed_tick <= '0';
                speed_counter <= (OTHERS => '0');
            ELSE
                IF speed_counter >= speed_target - 1 THEN
                    speed_counter <= (OTHERS => '0');
                    speed_tick <= '1';
                ELSE
                    speed_counter <= speed_counter + 1;
                    speed_tick <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    --============================================================================--
    -- 主控制进程
    -- 功能：根据选择的工作模式更新LED显示缓冲寄存器
    -- 模式说明：
    --   0-直接输出 1-闪烁 2-流水 3-星光
    -- 输出LED_Value_Seg寄存器
    --============================================================================--
    --LED模式切换
    PROCESS (LED_CLK, LED_RST)
    BEGIN
        IF LED_RST = '0' THEN
            led_state_mode <= NO_LIGHT;--无输出状态
            LED_Mode_prev <= "00";
        ELSIF rising_edge(LED_CLK) THEN
            --检测LED_Mode的变化
            IF LED_Mode /= LED_Mode_prev THEN
                CASE LED_Mode IS
                    WHEN "00" =>
                        led_state_mode <= NO_LIGHT;
                    WHEN "01" =>
                        led_state_mode <= FLOW_LIGHT;
                    WHEN "10" =>
                        led_state_mode <= BLINKING_LIGHT;
                    WHEN "11" =>
                        led_state_mode <= NO_LIGHT;
                END CASE;
                LED_Mode_prev <= LED_Mode;
            END IF;
        END IF;
    END PROCESS;

    ---------------------------------------
    -- LED控制逻辑
    PROCESS (LED_CLK, LED_RST)
    BEGIN
        IF LED_RST = '0' THEN
            ms_counter <= 0;
            flow_LED_reg <= "0000000001";
            LED_Value_Seg <= (OTHERS => '0');
        ELSIF rising_edge(LED_CLK) THEN
            -- 模式切换时的重置逻辑
            IF LED_Mode /= LED_Mode_prev THEN
                CASE led_state_mode IS
                    WHEN NO_LIGHT =>
                        LED_Value_Seg <= (OTHERS => '0'); -- 无灯状态
                    WHEN FLOW_LIGHT =>
                        flow_LED_reg <= "0000000001"; -- 重置流水灯寄存器
                        LED_Value_Seg <= flow_LED_reg; -- 初始状态
                    WHEN BLINKING_LIGHT =>
                        LED_Value_Seg <= "1111111111"; -- 初始状态为全亮
                    when FULL_LIGHT =>
                        LED_Value_Seg <= (OTHERS => '1');
                END CASE;
            END IF;

            -- 正常模式运行逻辑
            CASE led_state_mode IS
                WHEN NO_LIGHT =>
                    LED_Value_Seg <= (OTHERS => '0'); -- 无灯状态
                WHEN FLOW_LIGHT =>
                    CASE LED_Direction IS
                        WHEN "10" =>
                            IF ms_counter = (499999999 / (2 ** (TO_INTEGER(UNSIGNED(LED_Speed)) - 1))) THEN
                            --IF ms_counter = speed_counter THEN
                                ms_counter <= 0;
                                flow_LED_reg <= flow_LED_reg(8 DOWNTO 0) & flow_LED_reg(9); -- 正向循环左移
                            ELSE
                                ms_counter <= ms_counter + 1;
                            END IF;
                            LED_Value_Seg <= flow_LED_reg; -- 流水灯状态
                        WHEN "01" =>
                            IF ms_counter = (499999999 / (2 ** (TO_INTEGER(UNSIGNED(LED_Speed)) - 1))) THEN
                            --IF ms_counter = speed_counter THEN
                                ms_counter <= 0;
                                flow_LED_reg <= flow_LED_reg(0) & flow_LED_reg(9 DOWNTO 1); -- 反向循环右移
                            ELSE
                                ms_counter <= ms_counter + 1;
                            END IF;
                            LED_Value_Seg <= flow_LED_reg; -- 反向流水灯状态
                        WHEN OTHERS =>
                            NULL;
                    END CASE;
                WHEN BLINKING_LIGHT =>
                    CASE LED_Direction IS
                        WHEN "10" =>
                            IF ms_counter = (499999999 / (2 ** (TO_INTEGER(UNSIGNED(LED_Speed)) - 1))) THEN
                            --IF ms_counter =speed_counter THEN
                                ms_counter <= 0;
                                LED_Value_Seg <= NOT LED_Value_Seg; -- 切换 LED 状态
                            ELSE
                                ms_counter <= ms_counter + 1;
                            END IF;
                        WHEN OTHERS =>
                            NULL;
                    END CASE;
                when FULL_LIGHT =>
                    LED_Value_Seg <= (OTHERS => '1');
                WHEN OTHERS =>
                    NULL;
            END CASE;
        END IF;
    END PROCESS;

    --============================================================================--
    -- PWM生成进程
    -- 功能：根据亮度参数生成PWM信号，控制LED亮度
    -- 原理：16级PWM，占空比 = (LED_BRIGHT+1)/16
    --输入 LED_Value_Seg 寄存器，输出 pwm_output_reg 输出接口
    --============================================================================--
    PROCESS (LED_CLK, LED_RST)
    BEGIN
        IF LED_RST = '0' THEN -- 复位处理
            pwm_counter <= 0;
            pwm_output_reg <= (OTHERS => '0');
        ELSIF rising_edge(LED_CLK) THEN
            -- PWM计数器循环（0-15）
            pwm_counter <= (pwm_counter + 1) MOD (PWM_MAX + 1);

            -- 亮度比较器
            IF pwm_counter < UNSIGNED(LED_BRIGHT) THEN
                pwm_output_reg <= LED_Value_Seg; -- 高电平阶段：输出当前LED值
            ELSE
                pwm_output_reg <= (OTHERS => '0'); -- 低电平阶段：关闭所有LED
            END IF;
        END IF;
    END PROCESS;

    --============================================================================--
    -- 最终输出控制
    -- 功能：将PWM处理后的信号输出到物理引脚
    -- 注意：当使能无效时强制输出全0
    --============================================================================--
    LED_OUTPUT <= pwm_output_reg WHEN LED_Enable = '1' ELSE
        (OTHERS => '0');

END Behavioral;