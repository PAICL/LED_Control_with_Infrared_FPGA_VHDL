library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity CLK is
    Port (
        clk_RST       : in  STD_LOGIC;
        clk_50MHz_in  : in  STD_LOGIC;
        clk_1us_out  : out STD_LOGIC;
        clk_1ms_out  : out STD_LOGIC;
        clk_1s_out   : out STD_LOGIC
    );
end CLK;

architecture Behavioral of CLK is
    signal counter_1us : integer range 0 to 49 := 0;
    signal counter_1ms : integer range 0 to 49999 := 0;
    signal counter_1s  : integer range 0 to 49999999 := 0;
    signal clk_1us     : STD_LOGIC := '0';
    signal clk_1ms     : STD_LOGIC := '0';
    signal clk_1s      : STD_LOGIC := '0';
begin
    clk_1us_out <= clk_1us;
    clk_1ms_out <= clk_1ms;
    clk_1s_out  <= clk_1s;

    process(clk_50MHz_in)
    begin
        if rising_edge(clk_50MHz_in) then
            -- 同步复位
            if clk_RST = '0' then
                counter_1us <= 0;
                counter_1ms <= 0;
                counter_1s  <= 0;
                clk_1us     <= '0';
                clk_1ms     <= '0';
                clk_1s      <= '0';
            else
                -- 1μs时钟生成
                counter_1us <= counter_1us + 1;
                if counter_1us = 49 then
                    clk_1us     <= not clk_1us;
                    counter_1us <= 0;
                end if;

                -- 1ms时钟生成
                counter_1ms <= counter_1ms + 1;
                if counter_1ms = 49999 then
                    clk_1ms     <= not clk_1ms;
                    counter_1ms <= 0;
                end if;

                -- 1s时钟生成
                counter_1s <= counter_1s + 1;
                if counter_1s = 49999999 then
                    clk_1s     <= not clk_1s;
                    counter_1s <= 0;
                end if;
            end if;
        end if;
    end process;
end Behavioral;