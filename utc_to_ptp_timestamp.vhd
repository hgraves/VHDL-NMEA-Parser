library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity utc_to_ptp_timestamp is
    port (  
            CLK_IN                          : IN  STD_LOGIC;
            RST_IN                          : IN  STD_LOGIC;

            DO_CONV_IN                      : IN  STD_LOGIC;
            CONV_DONE_OUT                   : OUT  STD_LOGIC;
            
            BCD_UTC_YEAR_IN                 : IN  STD_LOGIC_VECTOR(15 downto 0);
            BCD_UTC_MONTH_IN                : IN  STD_LOGIC_VECTOR(7 downto 0);
            BCD_UTC_DAY_IN                  : IN  STD_LOGIC_VECTOR(7 downto 0);
            BCD_UTC_HOUR_IN                 : IN  STD_LOGIC_VECTOR(7 downto 0);
            BCD_UTC_MIN_IN                  : IN  STD_LOGIC_VECTOR(7 downto 0);
            BCD_UTC_SEC_IN                  : IN  STD_LOGIC_VECTOR(7 downto 0);

            UTC_TIMEZONE_HOUR_OFFSET_IN     : IN  STD_LOGIC_VECTOR(7 downto 0);
            UTC_LEAP_SEC_IN                 : IN  STD_LOGIC_VECTOR(7 downto 0);

            TIMESTAMP_OUT                   : OUT STD_LOGIC_VECTOR(31 downto 0));
end utc_to_ptp_timestamp;

architecture Behavioral of utc_to_ptp_timestamp is

constant C_1970_years_inv_bin   : unsigned(15 downto 0) := X"F84E";

constant C_one_thousand         : unsigned(11 downto 0) := X"3E8";
constant C_one_hundred          : unsigned(7 downto 0) := X"64";
constant C_ten                  : unsigned(3 downto 0) := X"A";

constant C_min_to_sec           : unsigned(15 downto 0)  := X"003C";
constant C_hour_to_sec          : unsigned(15 downto 0) := X"0E10";
constant C_day_to_sec           : unsigned(19 downto 0) := X"15180";
constant C_year_to_sec          : unsigned(24 downto 0) := '1'&X"E13380";

signal calc_state               : std_logic_vector(15 downto 0) := (others => '0');

signal utc_year_thousands_bin   : unsigned(15 downto 0) := (others => '0');
signal utc_year_hundreds_bin    : unsigned(15 downto 0) := (others => '0');
signal utc_year_tens_bin        : unsigned(15 downto 0) := (others => '0');
signal utc_year_bin             : unsigned(15 downto 0) := (others => '0');
signal utc_leap_days_bin        : unsigned(11 downto 0) := (others => '0');
signal utc_days_from_month_bin  : unsigned(11 downto 0) := (others => '0');
signal utc_day_bin              : unsigned(7 downto 0) := (others => '0');
signal utc_hour_bin             : unsigned(7 downto 0) := (others => '0');
signal utc_min_bin              : unsigned(7 downto 0) := (others => '0');
signal utc_sec_bin              : unsigned(7 downto 0) := (others => '0');

signal sec_from_years           : unsigned(31 downto 0) := (others => '0');
signal sec_from_months          : unsigned(31 downto 0) := (others => '0');
signal sec_from_days            : unsigned(31 downto 0) := (others => '0');
signal sec_from_leap_days       : unsigned(31 downto 0) := (others => '0');
signal sec_from_hours           : unsigned(31 downto 0) := (others => '0');
signal sec_from_min             : unsigned(31 downto 0) := (others => '0');

signal epoch_time_calc          : unsigned(31 downto 0) := (others => '0');

begin

    CONV_DONE_OUT <= calc_state(15);
    TIMESTAMP_OUT <= std_logic_vector(epoch_time_calc);

    STATE_PROC: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            calc_state(15 downto 1) <= calc_state(14 downto 0);
            if calc_state = X"0000" then
                calc_state(0) <= DO_CONV_IN;
            else
                calc_state(0) <= '0';
            end if;
        end if;
    end process;

    UTC_YEAR_CALC: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if calc_state(0) = '1' then
                utc_year_thousands_bin <= X"0000";
            elsif calc_state(1) = '1' then
                utc_year_thousands_bin <= C_one_thousand * unsigned(BCD_UTC_YEAR_IN(15 downto 12));
            end if;
            if calc_state(0) = '1' then
                utc_year_hundreds_bin <= X"0000";
            elsif calc_state(2) = '1' then
                utc_year_hundreds_bin <= C_one_hundred * unsigned(X"0"&BCD_UTC_YEAR_IN(11 downto 8));
            end if;
            if calc_state(0) = '1' then
                utc_year_tens_bin <= X"0000";
            elsif calc_state(3) = '1' then
                utc_year_tens_bin <= C_ten * unsigned(X"00"&BCD_UTC_YEAR_IN(7 downto 4));
            end if;
            if calc_state(0) = '1' then
                utc_year_bin <= unsigned(X"000" & BCD_UTC_YEAR_IN(3 downto 0));
            elsif calc_state(2) = '1' then
                utc_year_bin <= utc_year_bin + utc_year_thousands_bin;
            elsif calc_state(3) = '1' then
                utc_year_bin <= utc_year_bin + utc_year_hundreds_bin;
            elsif calc_state(4) = '1' then
                utc_year_bin <= utc_year_bin + utc_year_tens_bin;
            elsif calc_state(5) = '1' then
                utc_year_bin <= utc_year_bin + C_1970_years_inv_bin;
            end if;
        end if;
    end process;

    UTC_MONTH_CALC: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if calc_state(6) = '1' then
                if BCD_UTC_MONTH_IN = X"01" then
                    utc_days_from_month_bin <= X"000";
                elsif BCD_UTC_MONTH_IN = X"02" then
                    utc_days_from_month_bin <= X"01F";
                elsif BCD_UTC_MONTH_IN = X"03" then
                    if utc_year_bin(1 downto 0) = "00" then
                        utc_days_from_month_bin <= X"03C";
                    else
                        utc_days_from_month_bin <= X"03B";
                    end if;
                elsif BCD_UTC_MONTH_IN = X"04" then
                    if utc_year_bin(1 downto 0) = "00" then
                        utc_days_from_month_bin <= X"05B";
                    else
                        utc_days_from_month_bin <= X"05A";
                    end if;
                elsif BCD_UTC_MONTH_IN = X"05" then
                    if utc_year_bin(1 downto 0) = "00" then
                        utc_days_from_month_bin <= X"079";
                    else
                        utc_days_from_month_bin <= X"078";
                    end if;
                elsif BCD_UTC_MONTH_IN = X"06" then
                    if utc_year_bin(1 downto 0) = "00" then
                        utc_days_from_month_bin <= X"098";
                    else
                        utc_days_from_month_bin <= X"097";
                    end if;
                elsif BCD_UTC_MONTH_IN = X"07" then
                    if utc_year_bin(1 downto 0) = "00" then
                        utc_days_from_month_bin <= X"0B6";
                    else
                        utc_days_from_month_bin <= X"0B5";
                    end if;
                elsif BCD_UTC_MONTH_IN = X"08" then
                    if utc_year_bin(1 downto 0) = "00" then
                        utc_days_from_month_bin <= X"0D5";
                    else
                        utc_days_from_month_bin <= X"0D4";
                    end if;
                elsif BCD_UTC_MONTH_IN = X"09" then
                    if utc_year_bin(1 downto 0) = "00" then
                        utc_days_from_month_bin <= X"0F4";
                    else
                        utc_days_from_month_bin <= X"0F3";
                    end if;
                elsif BCD_UTC_MONTH_IN = X"10" then
                    if utc_year_bin(1 downto 0) = "00" then
                        utc_days_from_month_bin <= X"112";
                    else
                        utc_days_from_month_bin <= X"111";
                    end if;
                elsif BCD_UTC_MONTH_IN = X"11" then
                    if utc_year_bin(1 downto 0) = "00" then
                        utc_days_from_month_bin <= X"131";
                    else
                        utc_days_from_month_bin <= X"130";
                    end if;
                elsif BCD_UTC_MONTH_IN = X"12" then
                    if utc_year_bin(1 downto 0) = "00" then
                        utc_days_from_month_bin <= X"14F";
                    else
                        utc_days_from_month_bin <= X"14E";
                    end if;
                end if;
            end if;
        end if;
    end process;

    UTC_LEAP_DAYS_FROM_YEAR_CALC: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if calc_state(6) = '1' then
                utc_leap_days_bin <= utc_year_bin(13 downto 2);
            end if;
        end if;
    end process;

    UTC_DAY_CALC: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if calc_state(0) = '1' then
                utc_day_bin <= unsigned(BCD_UTC_DAY_IN(7 downto 4)) * C_ten;
            elsif calc_state(1) = '1' then
                utc_day_bin <= utc_day_bin + unsigned(X"0" & BCD_UTC_DAY_IN(3 downto 0));
            elsif calc_state(2) = '1' then
                utc_day_bin <= utc_day_bin + X"FF"; -- minus 1
            end if;
        end if;
    end process;

    UTC_HOUR_CALC: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if calc_state(0) = '1' then
                utc_hour_bin <= unsigned(BCD_UTC_HOUR_IN(7 downto 4)) * C_ten;
            elsif calc_state(1) = '1' then
                utc_hour_bin <= utc_hour_bin + unsigned(X"0" & BCD_UTC_HOUR_IN(3 downto 0));
            elsif calc_state(2) = '1' then
                utc_hour_bin <= utc_hour_bin + unsigned(UTC_TIMEZONE_HOUR_OFFSET_IN(7 downto 0));
            end if;
        end if;
    end process;

    UTC_MIN_CALC: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if calc_state(0) = '1' then
                utc_min_bin <= unsigned(BCD_UTC_MIN_IN(7 downto 4)) * C_ten;
            elsif calc_state(1) = '1' then
                utc_min_bin <= utc_min_bin + unsigned(X"0" & BCD_UTC_MIN_IN(3 downto 0));
            end if;
        end if;
    end process;

    UTC_SEC_CALC: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if calc_state(0) = '1' then
                utc_sec_bin <= unsigned(BCD_UTC_SEC_IN(7 downto 4)) * C_ten;
            elsif calc_state(1) = '1' then
                utc_sec_bin <= utc_sec_bin + unsigned(X"0" & BCD_UTC_SEC_IN(3 downto 0));
            end if;
        end if;
    end process;

    EPOCH_CALC: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if calc_state(0) = '1' then
                sec_from_years <= (others => '0');
            elsif calc_state(6) = '1' then
                sec_from_years <= utc_year_bin(6 downto 0) * C_year_to_sec;
            end if;
            if calc_state(1) = '1' then
                sec_from_months <= (others => '0');
            elsif calc_state(7) = '1' then
                sec_from_months <= utc_days_from_month_bin * C_day_to_sec;
            end if;
            if calc_state(2) = '1' then
                sec_from_days <= (others => '0');
            elsif calc_state(8) = '1' then
                sec_from_days <= (X"0"&utc_day_bin) * C_day_to_sec;
            end if;
            if calc_state(3) = '1' then
                sec_from_leap_days <= (others => '0');
            elsif calc_state(9) = '1' then
                sec_from_leap_days <= utc_leap_days_bin * C_day_to_sec;
            end if;
            if calc_state(4) = '1' then
                sec_from_hours <= (others => '0');
            elsif calc_state(10) = '1' then
                sec_from_hours <= (X"00"&utc_hour_bin) * C_hour_to_sec;
            end if;
            if calc_state(5) = '1' then
                sec_from_min <= (others => '0');
            elsif calc_state(11) = '1' then
                sec_from_min <= (X"00"&utc_min_bin) * C_min_to_sec;
            end if;
            if calc_state(7) = '1' then
                epoch_time_calc <= sec_from_years;
            elsif calc_state(8) = '1' then
                epoch_time_calc <= epoch_time_calc + sec_from_months;
            elsif calc_state(9) = '1' then
                epoch_time_calc <= epoch_time_calc + sec_from_days;
            elsif calc_state(10) = '1' then
                epoch_time_calc <= epoch_time_calc + sec_from_leap_days;
            elsif calc_state(11) = '1' then
                epoch_time_calc <= epoch_time_calc + sec_from_hours;
            elsif calc_state(12) = '1' then
                epoch_time_calc <= epoch_time_calc + sec_from_min;
            elsif calc_state(13) = '1' then
                epoch_time_calc <= epoch_time_calc + utc_sec_bin;
            elsif calc_state(14) = '1' then
                epoch_time_calc <= epoch_time_calc + unsigned(X"000000" & UTC_LEAP_SEC_IN);
            end if;
        end if;
    end process;

end Behavioral;