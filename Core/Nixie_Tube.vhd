LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY Nixie_Tube IS
    PORT (
        -- 控制信号
        SEG_Enable : IN STD_LOGIC; -- 数码管使能 (新增)
        SEG_RESET : IN STD_LOGIC; -- 数码管复位 (新增)

        -- 6组4位输入信号
        data0 : IN STD_LOGIC_VECTOR(3 DOWNTO 0); -- 数码管1数据
        data1 : IN STD_LOGIC_VECTOR(3 DOWNTO 0); -- 数码管2数据
        data2 : IN STD_LOGIC_VECTOR(3 DOWNTO 0); -- 数码管3数据
        data3 : IN STD_LOGIC_VECTOR(3 DOWNTO 0); -- 数码管4数据
        data4 : IN STD_LOGIC_VECTOR(3 DOWNTO 0); -- 数码管5数据
        data5 : IN STD_LOGIC_VECTOR(3 DOWNTO 0); -- 数码管6数据

        -- 6组7段输出信号
        seg_out0 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 数码管1
        seg_out1 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 数码管2
        seg_out2 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 数码管3 
        seg_out3 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 数码管4
        seg_out4 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 数码管5
        seg_out5 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0) -- 数码管6
    );
END Nixie_Tube;

ARCHITECTURE Behavioral OF Nixie_Tube IS
    -- 七段数码管译码函数
    FUNCTION seg_decode(data : STD_LOGIC_VECTOR(3 DOWNTO 0))
        RETURN STD_LOGIC_VECTOR IS
    BEGIN
        CASE data IS
            WHEN "0000" => RETURN "1000000"; -- 0
            WHEN "0001" => RETURN "1111001"; -- 1
            WHEN "0010" => RETURN "0100100"; -- 2
            WHEN "0011" => RETURN "0110000"; -- 3
            WHEN "0100" => RETURN "0011001"; -- 4
            WHEN "0101" => RETURN "0010010"; -- 5
            WHEN "0110" => RETURN "0000010"; -- 6
            WHEN "0111" => RETURN "1111000"; -- 7
            WHEN "1000" => RETURN "0000000"; -- 8
            WHEN "1001" => RETURN "0010000"; -- 9
            WHEN "1010" => RETURN "0001000"; -- A
            WHEN "1011" => RETURN "0000011"; -- B
            WHEN "1100" => RETURN "1000110"; -- C
            WHEN "1101" => RETURN "0100001"; -- D
            WHEN "1110" => RETURN "0000110"; -- E
            WHEN "1111" => RETURN "0001110"; -- F
            WHEN OTHERS => RETURN "1111111"; -- 熄灭
        END CASE;
    END FUNCTION;
BEGIN
    -- 并行生成6个译码器
    seg_out0 <= seg_decode(data0);
    seg_out1 <= seg_decode(data1);
    seg_out2 <= seg_decode(data2);
    seg_out3 <= seg_decode(data3);
    seg_out4 <= seg_decode(data4);
    seg_out5 <= seg_decode(data5);
END Behavioral;