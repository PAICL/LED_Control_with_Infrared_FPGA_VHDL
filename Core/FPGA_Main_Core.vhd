LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY FPGA_Main_Core IS
    PORT (
        -- 全局信号
        RST : IN STD_LOGIC; -- 全局复位
        CLK : IN STD_LOGIC; -- 50MHz主时钟

        -- 红外接口
        IR_RXD_Data : IN STD_LOGIC_VECTOR(7 DOWNTO 0); -- 解码数据
        Data_Enable : IN STD_LOGIC; -- 数据有效标志
        Repeat_Enable : IN STD_LOGIC; -- 重复帧标志

        -- LED控制接口
        LED_RST : OUT STD_LOGIC; -- LED复位
        LED_Enable : OUT STD_LOGIC; -- LED使能
        LED_Value : OUT STD_LOGIC_VECTOR(9 DOWNTO 0); -- LED数据值
        LED_BRIGHT : OUT STD_LOGIC_VECTOR(3 DOWNTO 0); -- 亮度参数
        LED_Direction : OUT STD_LOGIC_VECTOR(1 DOWNTO 0); -- LED方向控制
        LED_Speed : OUT STD_LOGIC_VECTOR(3 DOWNTO 0); -- LED速度控制
        LED_Mode : OUT STD_LOGIC_VECTOR(1 DOWNTO 0); -- LED模式控制

        -- 数码管接口
        SEG_Enable : OUT STD_LOGIC; -- 数码管使能
        SEG_RESET : OUT STD_LOGIC; -- 数码管复位
        SEG_Data0 : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        SEG_Data1 : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        SEG_Data2 : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        SEG_Data3 : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        SEG_Data4 : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        SEG_Data5 : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
    );
END FPGA_Main_Core;

ARCHITECTURE Behavioral OF FPGA_Main_Core IS

    --指令检测
    --200ms分频，用于检测指令检测使能
    SIGNAL counter_200ms : INTEGER RANGE 0 TO 9999999 := 0;
    SIGNAL clk_200ms : STD_LOGIC := '0';
    --指令使能寄存器
    SIGNAL IR_Data_Enable : STD_LOGIC := '0';

    -- 控制寄存器
    SIGNAL mode_reg : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00"; -- 模式寄存器（初始模式0）
    SIGNAL speed_reg : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1000"; -- 速度寄存器（默认8=1s）
    SIGNAL bright_reg : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1111";-- 亮度寄存器（最大亮度）
    SIGNAL dir_reg : STD_LOGIC_VECTOR(1 DOWNTO 0) := "10"; -- 方向寄存器
    SIGNAL led_value_reg : STD_LOGIC_VECTOR(9 DOWNTO 0) := (OTHERS => '0'); -- LED值缓存

    -- 命令码信号定义
    --SIGNAL last_ir_cmd : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    --SIGNAL cmd_active : STD_LOGIC := '0';

    -- 显示数据
    SIGNAL disp_mode : STD_LOGIC_VECTOR(3 DOWNTO 0); -- 模式显示值
    SIGNAL disp_speed : STD_LOGIC_VECTOR(7 DOWNTO 0); -- 速度显示值
    SIGNAL disp_bright : STD_LOGIC_VECTOR(7 DOWNTO 0); -- 亮度显示值

    -- 增强状态机设计
    TYPE state_type IS (
        POWER_OFF,
        MODE_SELECT,
        VALUE_SET,
        RUN_MODE,
        PAUSE
    );
    SIGNAL current_state : state_type := POWER_OFF;

    -- 红外数据变化检测
    SIGNAL prev_ir_data : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL data_changed : STD_LOGIC := '0';

    -- 数字键临时存储
    SIGNAL temp_digit : INTEGER RANGE 0 TO 9 := 0;

    -- 二进制到BCD转换函数
    FUNCTION bin2bcd(bin : STD_LOGIC_VECTOR(3 DOWNTO 0))
        RETURN STD_LOGIC_VECTOR IS
        VARIABLE bcd : STD_LOGIC_VECTOR(7 DOWNTO 0);
    BEGIN
        CASE bin IS
            WHEN "0000" => bcd := "00000000"; -- 0
            WHEN "0001" => bcd := "00000001"; -- 1
            WHEN "0010" => bcd := "00000010"; -- 2
            WHEN "0011" => bcd := "00000011"; -- 3
            WHEN "0100" => bcd := "00000100"; -- 4
            WHEN "0101" => bcd := "00000101"; -- 5
            WHEN "0110" => bcd := "00000110"; -- 6
            WHEN "0111" => bcd := "00000111"; -- 7
            WHEN "1000" => bcd := "00001000"; -- 8
            WHEN "1001" => bcd := "00001001"; -- 9
            WHEN "1010" => bcd := "00010000"; -- 10
            WHEN "1011" => bcd := "00010001"; -- 11
            WHEN "1100" => bcd := "00010010"; -- 12
            WHEN "1101" => bcd := "00010011"; -- 13
            WHEN "1110" => bcd := "00010100"; -- 14
            WHEN "1111" => bcd := "00010101"; -- 15
            WHEN OTHERS => bcd := "00000000";
        END CASE;
        RETURN bcd;
    END FUNCTION;

BEGIN
    -- 输出信号连接
    LED_RST <= RST;
    LED_Enable <= '1';
    --LED_Enable <= '1' WHEN mode_reg /= "00" ELSE
    --    '0'; -- 模式0时关闭LED
    LED_Value <= led_value_reg;
    LED_BRIGHT <= bright_reg;
    LED_Direction <= dir_reg;
    LED_Speed <= speed_reg;
    LED_Mode <= mode_reg;

    -- 显示数据转换
    disp_mode <= "00" & mode_reg;
    disp_speed <= bin2bcd(speed_reg);
    disp_bright <= bin2bcd(bright_reg);

    -- 数码管显示映射更新
   -- SEG_Data0 <= prev_ir_data(7 DOWNTO 4);
    --SEG_Data1 <= prev_ir_data(3 DOWNTO 0);
    SEG_Data0 <= disp_mode(3 DOWNTO 0); -- 显示模式
    SEG_Data1 <= prev_ir_data(3 DOWNTO 0); --用于测试目前状态机的运行状态
    SEG_Data2 <= disp_speed(7 DOWNTO 4); -- 速度十位
    SEG_Data3 <= disp_speed(3 DOWNTO 0); -- 速度个位
    SEG_Data4 <= disp_bright(7 DOWNTO 4); -- 亮度十位
    SEG_Data5 <= disp_bright(3 DOWNTO 0); -- 亮度个位
    -- 红外数据变化检测（保持不变）

    -- 未使用的数码管控制线
    SEG_Enable <= '1';
    SEG_RESET <= '1';

    PROCESS (mode_reg)
    BEGIN
        CASE mode_reg IS
            WHEN "00" =>
                disp_mode <= "000" & mode_reg(0);
            WHEN "01" =>
                disp_mode <= "0001";
            WHEN "10" =>
                disp_mode <= "0010";
            WHEN OTHERS =>
                disp_mode <= "0011";
        END CASE;
    END PROCESS;

    PROCESS (Data_Enable)
    BEGIN
        IF rising_edge(Data_Enable) THEN
            prev_ir_data <= IR_RXD_Data;
        END IF;
        IF RST = '0' THEN
            prev_ir_data <= "00000000";
        END IF;
    END PROCESS;

    --PROCESS (Data_Enable)
    --BEGIN
    --   IF rising_edge(Data_Enable) THEN
    --      prev_ir_data <= IR_RXD_Data;
    --      IF RST = '0' THEN
    --            counter_200ms <= 0;
    --          IR_Data_Enable <= '1';
    --        ELSE
    --           counter_200ms <= counter_200ms + 1;
    --            IF IR_Data_Enable = '0' AND counter_200ms = 9999999 THEN
    --                IR_Data_Enable <= '1';
    --          END IF;
    --       END IF;
    --   END IF;
    --END PROCESS;

    --PROCESS (CLK)
    --BEGIN
    --    IF rising_edge(CLK) THEN
    --        prev_ir_data <= IR_RXD_Data;
    --        data_changed <= '0';
    --        IF IR_RXD_Data /= prev_ir_data THEN
    --            data_changed <= '1';
    --        END IF;
    --    END IF;
    --END PROCESS;

    -- 主模式控制进程
    MODE_CONTROL : PROCESS (CLK, RST, Data_Enable)
    BEGIN
        IF RST = '0' THEN
            mode_reg <= "00"; -- 复位时进入模式0
        ELSIF rising_edge(Data_Enable) THEN
            --IF Data_Enable = '1' THEN
                CASE prev_ir_data IS
                    WHEN "00000001" => mode_reg <= "00"; -- 按键0：全灭
                    WHEN "00000010" => mode_reg <= "01"; -- 按键1：模式1
                    WHEN "00000011" => mode_reg <= "10"; -- 按键2：模式2
                    WHEN "00000100" => mode_reg <= "11"; -- 按键3：模式3
                    WHEN OTHERS => NULL; -- 忽略其他按键
                END CASE;
            --END IF;
        END IF;
    END PROCESS;

    -- 独立亮度控制进程
    BRIGHTNESS_CONTROL : PROCESS (CLK, RST, Data_Enable)
    BEGIN
        IF RST = '0' THEN
            bright_reg <= "1111"; -- 复位亮度最大值
        ELSIF rising_edge(Data_Enable) THEN
            --IF Data_Enable = '1' THEN
                CASE prev_ir_data IS
                    WHEN "00011011" => -- VOL+键
                        IF unsigned(bright_reg) < 15 THEN
                            bright_reg <= STD_LOGIC_VECTOR(unsigned(bright_reg) + 1);
                        END IF;
                    WHEN "00011111" => -- VOL-键
                        IF unsigned(bright_reg) > 0 THEN
                            bright_reg <= STD_LOGIC_VECTOR(unsigned(bright_reg) - 1);
                        END IF;
                    WHEN OTHERS => NULL;
                END CASE;
            --END IF;
        END IF;
    END PROCESS;

    -- 独立速度控制进程
    SPEED_CONTROL : PROCESS (CLK, RST, Data_Enable)
    BEGIN
        IF RST = '0' THEN
            speed_reg <= "1000"; -- 默认速度
        ELSIF rising_edge(Data_Enable) THEN
            --IF Data_Enable = '1' THEN
                CASE prev_ir_data IS
                    WHEN "00011010" => -- CH+键（加速）
                        IF unsigned(speed_reg) < 15 THEN
                            speed_reg <= STD_LOGIC_VECTOR(unsigned(speed_reg) + 1);
                        --    else speed_reg <= "1111";
                        END IF;
                    WHEN "00011110" => -- CH-键（减速）
                        IF unsigned(speed_reg) > 0 THEN
                            speed_reg <= STD_LOGIC_VECTOR(unsigned(speed_reg) - 1);
                        --    else speed_reg <= "0000";
                        END IF;
                    WHEN OTHERS => NULL;
                END CASE;
            --END IF;
        END IF;
    END PROCESS;

        -- 独立方向进程
    Direction_CONTROL : PROCESS (CLK, RST, Data_Enable)
    BEGIN
        IF RST = '0' THEN
            dir_reg <= "10"; -- 默认方向
        ELSIF rising_edge(Data_Enable) THEN
            --IF Data_Enable = '1' THEN
                CASE prev_ir_data IS
                    WHEN "00010100" => --向左
                        dir_reg <= "10";
                    WHEN "00011000" => --向右
                        dir_reg <= "01";
                    WHEN OTHERS => NULL;
                END CASE;
            --END IF;
        END IF;
    END PROCESS;

END Behavioral;