library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity nmea_parser is
    port (  
            CLK_IN                  : IN  STD_LOGIC;
            RST_IN                  : IN  STD_LOGIC; 
            
            NMEA_EN_IN              : IN  STD_LOGIC;
            NMEA_DATA_IN            : IN  STD_LOGIC_VECTOR(7 downto 0);

            NMEA_EN_OUT             : OUT STD_LOGIC;
            NMEA_DATA_OUT           : OUT STD_LOGIC_VECTOR(7 downto 0);
            NMEA_EN_ACK_IN          : IN STD_LOGIC;

            NEW_TIMESTAMP_EN_OUT    : OUT STD_LOGIC;
            TIMESTAMP_DATA_OUT      : OUT STD_LOGIC_VECTOR(31 downto 0);

            ADDR_IN                 : IN  STD_LOGIC_VECTOR(7 downto 0);
            DATA_OUT                : OUT  STD_LOGIC_VECTOR(7 downto 0));
end nmea_parser;

architecture Behavioral of nmea_parser is

subtype slv is std_logic_vector;

function to_slv(s: string) return std_logic_vector is 
    constant ss: string(1 to s'length) := s; 
    variable answer: std_logic_vector(1 to 8 * s'length); 
    variable p: integer; 
    variable c: integer; 
begin 
    for i in ss'range loop
        p := 8 * i;
        c := character'pos(ss(i));
        answer(p - 7 to p) := std_logic_vector(to_unsigned(c,8)); 
    end loop; 
    return answer;
end function;

COMPONENT TDP_RAM
    Generic (   G_DATA_A_SIZE   :natural :=8;
                G_ADDR_A_SIZE   :natural :=9;
                G_RELATION      :natural :=1;
                G_INIT_FILE     :string :="");--log2(SIZE_A/SIZE_B)
   Port (   CLK_A_IN    : in  STD_LOGIC;
            WE_A_IN     : in  STD_LOGIC;
            ADDR_A_IN   : in  STD_LOGIC_VECTOR (G_ADDR_A_SIZE-1 downto 0);
            DATA_A_IN   : in  STD_LOGIC_VECTOR (G_DATA_A_SIZE-1 downto 0);
            DATA_A_OUT  : out  STD_LOGIC_VECTOR (G_DATA_A_SIZE-1 downto 0);
            CLK_B_IN    : in  STD_LOGIC;
            WE_B_IN     : in  STD_LOGIC;
            ADDR_B_IN   : in  STD_LOGIC_VECTOR (G_ADDR_A_SIZE+G_RELATION-1 downto 0);
            DATA_B_IN   : in  STD_LOGIC_VECTOR (G_DATA_A_SIZE/(2**G_RELATION)-1 downto 0);
            DATA_B_OUT  : out STD_LOGIC_VECTOR (G_DATA_A_SIZE/(2**G_RELATION)-1 downto 0));
END COMPONENT;

COMPONENT utc_to_ptp_timestamp
    port (  
        CLK_IN                      : IN  STD_LOGIC;
        RST_IN                      : IN  STD_LOGIC;

        DO_CONV_IN                  : IN  STD_LOGIC;
        CONV_DONE_OUT               : OUT  STD_LOGIC;
        
        BCD_UTC_YEAR_IN             : IN  STD_LOGIC_VECTOR(15 downto 0);
        BCD_UTC_MONTH_IN            : IN  STD_LOGIC_VECTOR(7 downto 0);
        BCD_UTC_DAY_IN              : IN  STD_LOGIC_VECTOR(7 downto 0);
        BCD_UTC_HOUR_IN             : IN  STD_LOGIC_VECTOR(7 downto 0);
        BCD_UTC_MIN_IN              : IN  STD_LOGIC_VECTOR(7 downto 0);
        BCD_UTC_SEC_IN              : IN  STD_LOGIC_VECTOR(7 downto 0);

        UTC_TIMEZONE_HOUR_OFFSET_IN : IN  STD_LOGIC_VECTOR(7 downto 0);
        UTC_LEAP_SEC_IN             : IN  STD_LOGIC_VECTOR(7 downto 0);

        TIMESTAMP_OUT               : OUT STD_LOGIC_VECTOR(31 downto 0));
END COMPONENT;

constant C_start_sentence_delimiter                     : std_logic_vector(7 downto 0) := to_slv("$");
constant C_comma                                        : std_logic_vector(7 downto 0) := to_slv(",");
constant C_decimal_point                                : std_logic_vector(7 downto 0) := to_slv(".");
constant C_star                                         : std_logic_vector(7 downto 0) := to_slv("*");

constant C_max_comma_count                              : unsigned(7 downto 0) := X"1F";
constant C_km_per_hr_index                              : unsigned(7 downto 0) := X"07";
constant C_time_comma_count                             : unsigned(7 downto 0) := X"01";
constant C_is_locked_comma_count                        : unsigned(7 downto 0) := X"06";

constant C_GP                                           : std_logic_vector(15 downto 0) := to_slv("GP");
constant C_GPVTG                                        : std_logic_vector(39 downto 0) := to_slv("GPVTG");
constant C_GPGGA                                        : std_logic_vector(39 downto 0) := to_slv("GPGGA");
constant C_GPRMC                                        : std_logic_vector(39 downto 0) := to_slv("GPRMC");
constant C_GPGSA                                        : std_logic_vector(39 downto 0) := to_slv("GPGSA");
constant C_GPGSV                                        : std_logic_vector(39 downto 0) := to_slv("GPGSV");
constant C_GPZDA                                        : std_logic_vector(39 downto 0) := to_slv("GPZDA");

constant C_GPVTG_Return_State                           : std_logic_vector(3 downto 0) := X"0";
constant C_GPGGA_Return_State                           : std_logic_vector(3 downto 0) := X"1";
constant C_GPRMC_Return_State                           : std_logic_vector(3 downto 0) := X"2";
constant C_GPGSA_Return_State                           : std_logic_vector(3 downto 0) := X"3";
constant C_GPGSV_Return_State                           : std_logic_vector(3 downto 0) := X"4";
constant C_GPZDA_Return_State                           : std_logic_vector(3 downto 0) := X"5";

constant C_count_9600_baud                              : unsigned(19 downto 0) := X"19686";

signal nmea_en_prev, nmea_en                            : std_logic := '0';
signal nmea_data_ini_ini, nmea_data_ini, nmea_data      : std_logic_vector(7 downto 0) := (others => '0');
signal nmea_data_valid                                  : std_logic := '0';

signal nmea_tag_val                                     : std_logic_vector(23 downto 0) := (others => '0');
signal comma_count                                      : unsigned(7 downto 0) := (others => '0');
signal checksum_final, checksum_val                     : std_logic_vector(7 downto 0) := (others => '0');
signal checksum_parsed                                  : unsigned(7 downto 0) := (others => '0');

signal velocity_int_count, velocity_dec_count           : unsigned(3 downto 0) := (others => '0');
signal velocity_int_len, velocity_dec_len               : unsigned(3 downto 0) := (others => '0');
signal velocity_int_len_rd, velocity_dec_len_rd         : std_logic_vector(3 downto 0) := (others => '0');

signal velocity_int, velocity_dec                       : std_logic_vector(47 downto 0) := (others => '0');
signal velocity_int_rd, velocity_dec_rd                 : std_logic_vector(47 downto 0) := (others => '0');

signal state_after_checksum                             : std_logic_vector(3 downto 0) := (others => '0');

signal time_val, time_val_rd                            : std_logic_vector(47 downto 0) := (others => '0');
signal time_val_count                                   : unsigned(3 downto 0) := (others => '0');

signal is_locked, is_locked_rd                          : std_logic_vector(7 downto 0);

signal num_satellites, num_satellites_rd                : std_logic_vector(15 downto 0);
signal num_satellites_count, num_satellites_count_final : unsigned(3 downto 0) := (others => '0');
signal num_satellites_count_rd                          : std_logic_vector(3 downto 0);

signal gps_config_addr                                  : unsigned(7 downto 0) := (others => '0');
signal gps_config_data                                  : std_logic_vector(7 downto 0);

signal startup_delay_count                              : unsigned(27 downto 0) := (others => '1'); -- roughly 2.6 seconds @ 100 MHZ;
signal startup_delay_count_debug                        : unsigned(27 downto 0) := (others => '0'); -- when running test bench

signal count_9600_baud                                  : unsigned(19 downto 0) := C_count_9600_baud;

signal utc_count                                        : unsigned(3 downto 0) := (others => '0');
signal utc, utc_rd                                      : std_logic_vector(47 downto 0) := (others => '0');
signal day_count, month_count                           : unsigned(3 downto 0) := (others => '0');
signal month, month_rd, day, day_rd                     : std_logic_vector(15 downto 0) := (others => '0');
signal year_count                                       : unsigned(3 downto 0) := (others => '0');
signal year, year_rd                                    : std_logic_vector(31 downto 0) := (others => '0');
signal local_zone, local_zone_rd                        : std_logic_vector(15 downto 0) := (others => '0');
signal lz_count                                         : unsigned(3 downto 0) := (others => '0');

signal year_bcd                                         : std_logic_vector(15 downto 0);
signal hour_bcd, month_bcd, day_bcd, min_bcd, sec_bcd   : std_logic_vector(7 downto 0);
signal perform_utc_to_timestamp_conv 						  : std_logic := '0';

type NMEA_PARSE_STATE is (
                            STARTUP_DELAY,
                            WRITE_GPS_CONFIGURATION0,
                            WRITE_GPS_CONFIGURATION1,
                            WRITE_GPS_CONFIGURATION2,
                            WRITE_GPS_CONFIGURATION3,
                            WRITE_GPS_CONFIGURATION4,
                            WRITE_GPS_CONFIGURATION5,

                            IDLE,
                            RECEIVED_START_DELIM,
                            RECEIVED_START_OF_TAG,
                            COLLECT_TAG_VAL0,
                            COLLECT_TAG_VAL1,
                            COLLECT_TAG_VAL2,
                            PARSE_TAG_VAL,

                            PARSE_GPVTG_SENTENCE0,
                            PARSE_GPVTG_SENTENCE1,
                            PARSE_GPVTG_SENTENCE2,
                            PARSE_GPVTG_SENTENCE3,

                            PARSE_GPGGA_SENTENCE0,
                            PARSE_GPGGA_SENTENCE1,
                            PARSE_GPGGA_SENTENCE2,
                            PARSE_GPGGA_SENTENCE3,
                            PARSE_GPGGA_SENTENCE4,

                            PARSE_GPRMC_SENTENCE0, -- TODO
                            PARSE_GPGSA_SENTENCE0, -- TODO
                            PARSE_GPGSV_SENTENCE0, -- TODO

                            PARSE_GPZDA_SENTENCE0,
                            PARSE_GPZDA_SENTENCE1,
                            PARSE_GPZDA_SENTENCE2,
                            PARSE_GPZDA_SENTENCE3,
                            PARSE_GPZDA_SENTENCE4,
                            PARSE_GPZDA_SENTENCE5,

                            GET_CHECKSUM,
                            PARSE_CHECKSUM0,
                            PARSE_CHECKSUM1,

                            CHECK_CHECKSUM,
                            GOTO_POST_CHECKSUM_STATE,

                            WRITE_GPVTG_VALUES,
                            WRITE_GPGGA_VALUES,
                            WRITE_GPZDA_VALUES,

                            COMPLETE
                        );

signal np_st, np_st_next : NMEA_PARSE_STATE := STARTUP_DELAY;

begin

    NMEA_DATA_VALID_PROC: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            nmea_data_ini_ini <= NMEA_DATA_IN;
            nmea_data_ini <= nmea_data_ini_ini;
            nmea_data <= nmea_data_ini;
            nmea_en <= NMEA_EN_IN;
            nmea_en_prev <= nmea_en;
            if nmea_en_prev = '1' and nmea_en = '0' then
                nmea_data_valid <= '1';
            else    
                nmea_data_valid <= '0';
            end if;
        end if;
    end process;

    STARTUP_DELAY_PROC: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            startup_delay_count <= startup_delay_count - 1;
        end if;
    end process;

    NMEA_PARSE_STATE_NEXT: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            np_st <= np_st_next;
        end if;
    end process;

    MAIN_STATE_DECODE: process (np_st, startup_delay_count, startup_delay_count_debug, state_after_checksum,
											NMEA_EN_ACK_IN, nmea_data_valid, nmea_data, nmea_tag_val, comma_count)
    begin
        np_st_next <= np_st; -- default to remain in same state
        case (np_st) is
            when STARTUP_DELAY =>
                if startup_delay_count = X"0000000" then
                --if startup_delay_count_debug = X"0000000" then
                    np_st_next <= WRITE_GPS_CONFIGURATION0;
                    --np_st_next <= IDLE; -- DEBUG ONLY
                end if;

            when WRITE_GPS_CONFIGURATION0 =>
                np_st_next <= WRITE_GPS_CONFIGURATION1;
            when WRITE_GPS_CONFIGURATION1 =>
                np_st_next <= WRITE_GPS_CONFIGURATION2;
            when WRITE_GPS_CONFIGURATION2 =>
                if gps_config_data = X"FF" or gps_config_addr = X"FF" then
                    np_st_next <= IDLE;
                else
                    np_st_next <= WRITE_GPS_CONFIGURATION3;
                end if;
            when WRITE_GPS_CONFIGURATION3 =>
                if NMEA_EN_ACK_IN = '1' then
                    np_st_next <= WRITE_GPS_CONFIGURATION4;
                end if;
            when WRITE_GPS_CONFIGURATION4 =>
                np_st_next <= WRITE_GPS_CONFIGURATION5;
            when WRITE_GPS_CONFIGURATION5 =>
                if count_9600_baud = X"00000" then
                    np_st_next <= WRITE_GPS_CONFIGURATION0;
                end if;

            when IDLE =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_start_sentence_delimiter then
                        np_st_next <= RECEIVED_START_DELIM;
                    end if;
                end if;

            when RECEIVED_START_DELIM =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_GP(15 downto 8) then
                        np_st_next <= RECEIVED_START_OF_TAG;
                    else
                        np_st_next <= COMPLETE;
                    end if;
                end if;
            when RECEIVED_START_OF_TAG =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_GP(7 downto 0) then
                        np_st_next <= COLLECT_TAG_VAL0;
                    else
                        np_st_next <= COMPLETE;
                    end if;
                end if;

            when COLLECT_TAG_VAL0 =>
                if nmea_data_valid = '1' then
                    np_st_next <= COLLECT_TAG_VAL1;
                end if;
            when COLLECT_TAG_VAL1 =>
                if nmea_data_valid = '1' then
                    np_st_next <= COLLECT_TAG_VAL2;
                end if;
            when COLLECT_TAG_VAL2 =>
                if nmea_data_valid = '1' then
                    np_st_next <= PARSE_TAG_VAL;
                end if;

            when PARSE_TAG_VAL =>
                if nmea_tag_val = C_GPVTG(23 downto 0) then
                    np_st_next <= PARSE_GPVTG_SENTENCE0;
                elsif nmea_tag_val = C_GPGGA(23 downto 0) then
                    np_st_next <= PARSE_GPGGA_SENTENCE0;
                elsif nmea_tag_val = C_GPRMC(23 downto 0) then
                    np_st_next <= PARSE_GPRMC_SENTENCE0;
                elsif nmea_tag_val = C_GPGSA(23 downto 0) then
                    np_st_next <= PARSE_GPGSA_SENTENCE0;
                elsif nmea_tag_val = C_GPGSV(23 downto 0) then
                    np_st_next <= PARSE_GPGSV_SENTENCE0;
                elsif nmea_tag_val = C_GPZDA(23 downto 0) then
                    np_st_next <= PARSE_GPZDA_SENTENCE0;
                else
                    np_st_next <= COMPLETE;
                end if;

            when PARSE_GPVTG_SENTENCE0 =>
                if comma_count = C_km_per_hr_index then
                    np_st_next <= PARSE_GPVTG_SENTENCE1;
                elsif comma_count = C_max_comma_count then
                    np_st_next <= COMPLETE;
                end if;
            when PARSE_GPVTG_SENTENCE1 =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_decimal_point then
                        np_st_next <= PARSE_GPVTG_SENTENCE2;
                    elsif nmea_data = C_comma then
                        np_st_next <= GET_CHECKSUM;
                    end if;
                end if;
            when PARSE_GPVTG_SENTENCE2 =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_comma then
                        np_st_next <= PARSE_GPVTG_SENTENCE3;
                    end if;
                end if;
            when PARSE_GPVTG_SENTENCE3 =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_comma then
                        np_st_next <= GET_CHECKSUM;
                    end if;
                end if;

            when PARSE_GPGGA_SENTENCE0 =>
                if comma_count = C_time_comma_count then
                    np_st_next <= PARSE_GPGGA_SENTENCE1;
                elsif comma_count = C_max_comma_count then
                    np_st_next <= COMPLETE;
                end if;
            when PARSE_GPGGA_SENTENCE1 =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_comma then
                        np_st_next <= PARSE_GPGGA_SENTENCE2;
                    end if;
                end if;
            when PARSE_GPGGA_SENTENCE2 =>
                if nmea_data_valid = '1' then
                    if comma_count = C_is_locked_comma_count then
                        np_st_next <= PARSE_GPGGA_SENTENCE3;
                    end if;
                end if;
            when PARSE_GPGGA_SENTENCE3 =>
                if nmea_data_valid = '1' then
                    np_st_next <= PARSE_GPGGA_SENTENCE4;
                end if;
            when PARSE_GPGGA_SENTENCE4 =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_comma then
                        np_st_next <= GET_CHECKSUM;
                    end if;
                end if;

            when PARSE_GPRMC_SENTENCE0 =>
                np_st_next <= COMPLETE;

            when PARSE_GPGSA_SENTENCE0 =>
                np_st_next <= COMPLETE;

            when PARSE_GPGSV_SENTENCE0 =>
                np_st_next <= COMPLETE;

            when PARSE_GPZDA_SENTENCE0 =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_comma then
                        np_st_next <= PARSE_GPZDA_SENTENCE1;
                    end if;
                end if;
            when PARSE_GPZDA_SENTENCE1 =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_comma then
                        np_st_next <= PARSE_GPZDA_SENTENCE2;
                    end if;
                end if;
            when PARSE_GPZDA_SENTENCE2 =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_comma then
                        np_st_next <= PARSE_GPZDA_SENTENCE3;
                    end if;
                end if;
            when PARSE_GPZDA_SENTENCE3 =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_comma then
                        np_st_next <= PARSE_GPZDA_SENTENCE4;
                    end if;
                end if;
            when PARSE_GPZDA_SENTENCE4 =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_comma then
                        np_st_next <= PARSE_GPZDA_SENTENCE5;
                    end if;
                end if;
            when PARSE_GPZDA_SENTENCE5 =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_comma then
                        np_st_next <= GET_CHECKSUM;
                    end if;
                end if;

            when GET_CHECKSUM =>
                if nmea_data_valid = '1' then
                    if nmea_data = C_star then
                        np_st_next <= PARSE_CHECKSUM0;
                    end if;
                end if;
            when PARSE_CHECKSUM0 =>
                if nmea_data_valid = '1' then
                    np_st_next <= PARSE_CHECKSUM1;
                end if;
            when PARSE_CHECKSUM1 =>
                if nmea_data_valid = '1' then
                    np_st_next <= CHECK_CHECKSUM;
                end if;
            when CHECK_CHECKSUM =>
                if checksum_parsed = unsigned(checksum_final) then
                    np_st_next <= GOTO_POST_CHECKSUM_STATE;
                else
                    np_st_next <= COMPLETE;
                end if;
            when GOTO_POST_CHECKSUM_STATE =>
                if state_after_checksum = C_GPVTG_Return_State then
                    np_st_next <= WRITE_GPVTG_VALUES;
                elsif state_after_checksum = C_GPGGA_Return_State then
                    np_st_next <= WRITE_GPGGA_VALUES;
                elsif state_after_checksum = C_GPRMC_Return_State then -- TODO
                    np_st_next <= COMPLETE;
                elsif state_after_checksum = C_GPGSA_Return_State then -- TODO
                    np_st_next <= COMPLETE;
                elsif state_after_checksum = C_GPGSV_Return_State then -- TODO
                    np_st_next <= COMPLETE;
                elsif state_after_checksum = C_GPZDA_Return_State then -- TODO
                    np_st_next <= WRITE_GPZDA_VALUES;
                end if;

            when WRITE_GPVTG_VALUES =>
                np_st_next <= COMPLETE;
            when WRITE_GPGGA_VALUES =>
                np_st_next <= COMPLETE;
            when WRITE_GPZDA_VALUES =>
                np_st_next <= COMPLETE;

            when COMPLETE =>
                np_st_next <= IDLE;

        end case;
    end process;

    COLLECT_TAG: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if nmea_data_valid = '1' then
                if np_st = COLLECT_TAG_VAL0 then
                    nmea_tag_val(23 downto 16) <= nmea_data;
                elsif np_st = COLLECT_TAG_VAL1 then
                    nmea_tag_val(15 downto 8) <= nmea_data;
                elsif np_st = COLLECT_TAG_VAL2 then
                    nmea_tag_val(7 downto 0) <= nmea_data;
                end if;
            end if;
        end if;
    end process;

    NUM_COMMAS: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if nmea_data_valid = '1' then
                if np_st = COLLECT_TAG_VAL2 then
                    comma_count <= (others => '0');
                elsif nmea_data = C_comma then
                    comma_count <= comma_count + 1;
                end if;
            end if;
        end if;
    end process;

    CHECKSUM: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if nmea_data_valid = '1' then
                if np_st = IDLE then
                    checksum_val <= (others => '0');
                else
                    checksum_val <= checksum_val xor nmea_data;
                end if;
                if np_st = GET_CHECKSUM then
                    checksum_final <= checksum_val;
                end if;
            end if;
        end if;
    end process;

    GPGVTG_PARSE: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if nmea_data_valid = '1' then
                if np_st = PARSE_GPVTG_SENTENCE1 then
                    if velocity_int_count = X"0" then
                        velocity_int(47 downto 40) <= nmea_data;
                    elsif velocity_int_count = X"1" then
                        velocity_int(39 downto 32) <= nmea_data;
                    elsif velocity_int_count = X"2" then
                        velocity_int(31 downto 24) <= nmea_data;
                    elsif velocity_int_count = X"3" then
                        velocity_int(23 downto 16) <= nmea_data;
                    elsif velocity_int_count = X"4" then
                        velocity_int(15 downto 8) <= nmea_data;
                    elsif velocity_int_count = X"5" then
                        velocity_int(7 downto 0) <= nmea_data;
                    end if;
                end if;
                if np_st = PARSE_GPVTG_SENTENCE1 then
                    velocity_int_count <= velocity_int_count + 1;
                else
                    velocity_int_count <= X"0";
                end if;
                if np_st = PARSE_GPVTG_SENTENCE1 then
                    velocity_int_len <= velocity_int_count;
                end if;
                if np_st = PARSE_GPVTG_SENTENCE2 then
                    if velocity_dec_count = X"0" then
                        velocity_dec(47 downto 40) <= nmea_data;
                    elsif velocity_dec_count = X"1" then
                        velocity_dec(39 downto 32) <= nmea_data;
                    elsif velocity_dec_count = X"2" then
                        velocity_dec(31 downto 24) <= nmea_data;
                    elsif velocity_dec_count = X"3" then
                        velocity_dec(23 downto 16) <= nmea_data;
                    elsif velocity_dec_count = X"4" then
                        velocity_dec(15 downto 8) <= nmea_data;
                    elsif velocity_dec_count = X"5" then
                        velocity_dec(7 downto 0) <= nmea_data;
                    end if;
                end if;
                if np_st = PARSE_GPVTG_SENTENCE2 then
                    velocity_dec_count <= velocity_dec_count + 1;
                else
                    velocity_dec_count <= X"0";
                end if;
                if np_st = PARSE_GPVTG_SENTENCE2 then
                    velocity_dec_len <= velocity_dec_count;
                end if;
            end if;
        end if;
    end process;

    GPGGA_PARSE: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if nmea_data_valid = '1' then
                if np_st = PARSE_GPGGA_SENTENCE1 then
                    if time_val_count = X"0" then
                        time_val(47 downto 40) <= nmea_data;
                    elsif time_val_count = X"1" then
                        time_val(39 downto 32) <= nmea_data;
                    elsif time_val_count = X"2" then
                        time_val(31 downto 24) <= nmea_data;
                    elsif time_val_count = X"3" then
                        time_val(23 downto 16) <= nmea_data;
                    elsif time_val_count = X"4" then
                        time_val(15 downto 8) <= nmea_data;
                    elsif time_val_count = X"5" then
                        time_val(7 downto 0) <= nmea_data;
                    end if;
                end if;
                if np_st = PARSE_GPGGA_SENTENCE1 then
                    time_val_count <= time_val_count + 1;
                else
                    time_val_count <= X"0";
                end if;
                if np_st = PARSE_GPGGA_SENTENCE2 then
                    if nmea_data /= C_comma then
                        is_locked <= nmea_data;
                    end if;
                end if;
                if np_st = PARSE_GPGGA_SENTENCE4 then
                    if num_satellites_count = X"0" then
                        num_satellites(15 downto 8) <= nmea_data;
                    elsif num_satellites_count = X"1" then
                        num_satellites(7 downto 0) <= nmea_data;
                    end if;
                end if;
                if np_st = PARSE_GPGGA_SENTENCE4 then
                    num_satellites_count <= num_satellites_count + 1;
                else
                    num_satellites_count <= X"0";
                end if;
                if np_st = PARSE_GPGGA_SENTENCE4 then
                    num_satellites_count_final <= num_satellites_count;
                end if;
            end if;
        end if;
    end process;

    GET_CHECKSUM_VAL: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if nmea_data_valid = '1' then
                if np_st = PARSE_CHECKSUM0 then
                    if nmea_data(7 downto 4) = X"3" then
                        checksum_parsed(7 downto 4) <= unsigned(nmea_data(3 downto 0));
                    else
                        checksum_parsed(7 downto 4) <= unsigned(nmea_data(3 downto 0)) + 9;
                    end if;
                elsif np_st = PARSE_CHECKSUM1 then
                    if nmea_data(7 downto 4) = X"3" then
                        checksum_parsed(3 downto 0) <= unsigned(nmea_data(3 downto 0));
                    else
                        checksum_parsed(3 downto 0) <= unsigned(nmea_data(3 downto 0)) + 9;
                    end if;
                end if;
            end if;
        end if;
    end process;

    RETURN_STATE: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if np_st = PARSE_GPVTG_SENTENCE0 then
                state_after_checksum <= C_GPVTG_Return_State;
            elsif np_st = PARSE_GPGGA_SENTENCE0 then
                state_after_checksum <= C_GPGGA_Return_State;
            elsif np_st = PARSE_GPRMC_SENTENCE0 then
                state_after_checksum <= C_GPRMC_Return_State;
            elsif np_st = PARSE_GPGSA_SENTENCE0 then
                state_after_checksum <= C_GPGSA_Return_State;
            elsif np_st = PARSE_GPGSV_SENTENCE0 then
                state_after_checksum <= C_GPGSV_Return_State;
            elsif np_st = PARSE_GPZDA_SENTENCE0 then
                state_after_checksum <= C_GPZDA_Return_State;
            end if;
        end if;
    end process;

    WRITE_VALUES: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if np_st = WRITE_GPVTG_VALUES then
                velocity_int_len_rd <= slv(velocity_int_len);
                velocity_dec_len_rd <= slv(velocity_dec_len);
                velocity_int_rd <= slv(velocity_int);
                velocity_dec_rd <= slv(velocity_dec);
            end if;
            if np_st = WRITE_GPGGA_VALUES then
                time_val_rd <= slv(time_val);
                is_locked_rd <= slv(is_locked);
                num_satellites_rd <= slv(num_satellites);
                num_satellites_count_rd <= slv(num_satellites_count);
            end if;
            if np_st = WRITE_GPZDA_VALUES then
                utc_rd <= utc;
                month_rd <= month;
                day_rd <= day;
                year_rd <= year;
                local_zone_rd <= local_zone;
            end if;
            if np_st = WRITE_GPZDA_VALUES then
                perform_utc_to_timestamp_conv <= '1';
            else
                perform_utc_to_timestamp_conv <= '0';
            end if;
        end if;
    end process;

    year_bcd <= year_rd(27 downto 24) & year_rd(19 downto 16) & year_rd(11 downto 8) & year_rd(3 downto 0);
    month_bcd <= month_rd(11 downto 8) & month_rd(3 downto 0);
    day_bcd <= day_rd(11 downto 8) & day_rd(3 downto 0);

    hour_bcd <= utc_rd(43 downto 40) & utc_rd(35 downto 32);
    min_bcd <= utc_rd(27 downto 24) & utc_rd(19 downto 16);
    sec_bcd <= utc_rd(11 downto 8) & utc_rd(3 downto 0);

    UTC_to_ptp_timestamp_inst : utc_to_ptp_timestamp
    port map (  
        CLK_IN                      => CLK_IN,
        RST_IN                      => '0',

        DO_CONV_IN                  => perform_utc_to_timestamp_conv,
        CONV_DONE_OUT               => NEW_TIMESTAMP_EN_OUT,

        BCD_UTC_YEAR_IN             => year_bcd,
        BCD_UTC_MONTH_IN            => month_bcd,
        BCD_UTC_DAY_IN              => day_bcd,
        BCD_UTC_HOUR_IN             => hour_bcd,
        BCD_UTC_MIN_IN              => min_bcd,
        BCD_UTC_SEC_IN              => sec_bcd,

        UTC_TIMEZONE_HOUR_OFFSET_IN => X"0A",
        UTC_LEAP_SEC_IN             => X"1A",

        TIMESTAMP_OUT               => TIMESTAMP_DATA_OUT);

    GPGZDA_PARSE: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if nmea_data_valid = '1' then
                if np_st = PARSE_GPZDA_SENTENCE1 then
                    if utc_count = X"0" then
                        utc(47 downto 40) <= nmea_data;
                    elsif utc_count = X"1" then
                        utc(39 downto 32) <= nmea_data;
                    elsif utc_count = X"2" then
                        utc(31 downto 24) <= nmea_data;
                    elsif utc_count = X"3" then
                        utc(23 downto 16) <= nmea_data;
                    elsif utc_count = X"4" then
                        utc(15 downto 8) <= nmea_data;
                    elsif utc_count = X"5" then
                        utc(7 downto 0) <= nmea_data;
                    end if;
                end if;
            end if;
            if nmea_data_valid = '1' then
                if np_st = PARSE_GPZDA_SENTENCE0 then
                    utc_count <= (others => '0');
                elsif np_st = PARSE_GPZDA_SENTENCE1 then
                    utc_count <= utc_count + 1;
                end if;
            end if;
            if nmea_data_valid = '1' then
                if np_st = PARSE_GPZDA_SENTENCE2 then
                    if day_count = X"0" then
                        day(15 downto 8) <= nmea_data;
                    elsif day_count = X"1" then
                        day(7 downto 0) <= nmea_data;
                    end if;
                end if;
            end if;
            if nmea_data_valid = '1' then
                if np_st = PARSE_GPZDA_SENTENCE1 then
                    day_count <= (others => '0');
                elsif np_st = PARSE_GPZDA_SENTENCE2 then
                    day_count <= day_count + 1;
                end if;
            end if;
            if nmea_data_valid = '1' then
                if np_st = PARSE_GPZDA_SENTENCE3 then
                    if month_count = X"0" then
                        month(15 downto 8) <= nmea_data;
                    elsif month_count = X"1" then
                        month(7 downto 0) <= nmea_data;
                    end if;
                end if;
            end if;
            if nmea_data_valid = '1' then
                if np_st = PARSE_GPZDA_SENTENCE2 then
                    month_count <= (others => '0');
                elsif np_st = PARSE_GPZDA_SENTENCE3 then
                    month_count <= month_count + 1;
                end if;
            end if;
            if nmea_data_valid = '1' then
                if np_st = PARSE_GPZDA_SENTENCE4 then
                    if year_count = X"0" then
                        year(31 downto 24) <= nmea_data;
                    elsif year_count = X"1" then
                        year(23 downto 16) <= nmea_data;
                    elsif year_count = X"2" then
                        year(15 downto 8) <= nmea_data;
                    elsif year_count = X"3" then
                        year(7 downto 0) <= nmea_data;
                    end if;
                end if;
            end if;
            if nmea_data_valid = '1' then
                if np_st = PARSE_GPZDA_SENTENCE3 then
                    year_count <= (others => '0');
                elsif np_st = PARSE_GPZDA_SENTENCE4 then
                    year_count <= year_count + 1;
                end if;
            end if;
            if nmea_data_valid = '1' then
                if np_st = PARSE_GPZDA_SENTENCE5 then
                    if lz_count = X"0" then
                        if nmea_data = C_comma then
                            local_zone(15 downto 8) <= X"00";
                        else
                            local_zone(15 downto 8) <= nmea_data;
                        end if;
                    elsif lz_count = X"1" then
                        if nmea_data = C_comma then
                            local_zone(7 downto 0) <= X"00";
                        else
                            local_zone(7 downto 0) <= nmea_data;
                        end if;
                    end if;
                end if;
            end if;
            if nmea_data_valid = '1' then
                if np_st = PARSE_GPZDA_SENTENCE4 then
                    lz_count <= (others => '0');
                elsif np_st = PARSE_GPZDA_SENTENCE5 then
                    lz_count <= lz_count + 1;
                end if;
            end if;
        end if;
    end process;

    GSP_CONFIG_ADDR: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if np_st = STARTUP_DELAY then
                gps_config_addr <= (others => '0');
            elsif np_st = WRITE_GPS_CONFIGURATION4 then
                gps_config_addr <= gps_config_addr + 1;
            end if;
            if np_st = WRITE_GPS_CONFIGURATION4 then
                count_9600_baud <= C_count_9600_baud;
            else
                count_9600_baud <= count_9600_baud - 1;
            end if;
        end if;
    end process;

    NMEA_EN_OUT <= '1' when np_st = WRITE_GPS_CONFIGURATION3 else '0';
    NMEA_DATA_OUT <= gps_config_data;

    GPS_Configure_instructions : TDP_RAM
        Generic Map(    G_DATA_A_SIZE   => 8,
                        G_ADDR_A_SIZE   => 8,
                        G_RELATION      => 0, 
                        G_INIT_FILE     => "./coe_dir/SIRF_3_GPS.coe")

        Port Map (      CLK_A_IN        => CLK_IN,
                        WE_A_IN         => '0',
                        ADDR_A_IN       => slv(gps_config_addr),
                        DATA_A_IN       => (others => '0'),
                        DATA_A_OUT      => gps_config_data,
                        CLK_B_IN        => '0',
                        WE_B_IN         => '0',
                        ADDR_B_IN       => (others => '0'),
                        DATA_B_IN       => (others => '0'),
                        DATA_B_OUT      => open);

    READ_DATA: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if ADDR_IN = X"00" then
                DATA_OUT <= X"0"&velocity_int_len_rd;
            elsif ADDR_IN = X"01" then
                DATA_OUT <= velocity_int_rd(47 downto 40);
            elsif ADDR_IN = X"02" then
                DATA_OUT <= velocity_int_rd(39 downto 32);
            elsif ADDR_IN = X"03" then
                DATA_OUT <= velocity_int_rd(31 downto 24);
            elsif ADDR_IN = X"04" then
                DATA_OUT <= velocity_int_rd(23 downto 16);
            elsif ADDR_IN = X"05" then
                DATA_OUT <= velocity_int_rd(15 downto 8);
            elsif ADDR_IN = X"06" then
                DATA_OUT <= velocity_int_rd(7 downto 0);
            elsif ADDR_IN = X"07" then
                DATA_OUT <= X"0"&velocity_dec_len_rd;
            elsif ADDR_IN = X"08" then
                DATA_OUT <= velocity_dec_rd(47 downto 40);
            elsif ADDR_IN = X"09" then
                DATA_OUT <= velocity_dec_rd(39 downto 32);
            elsif ADDR_IN = X"0A" then
                DATA_OUT <= velocity_dec_rd(31 downto 24);
            elsif ADDR_IN = X"0B" then
                DATA_OUT <= velocity_dec_rd(23 downto 16);
            elsif ADDR_IN = X"0C" then
                DATA_OUT <= velocity_dec_rd(15 downto 8);
            elsif ADDR_IN = X"0D" then
                DATA_OUT <= velocity_dec_rd(7 downto 0);
            elsif ADDR_IN = X"0E" then
                DATA_OUT <= time_val_rd(47 downto 40);
            elsif ADDR_IN = X"0F" then
                DATA_OUT <= time_val_rd(39 downto 32);
            elsif ADDR_IN = X"10" then
                DATA_OUT <= time_val_rd(31 downto 24);
            elsif ADDR_IN = X"11" then
                DATA_OUT <= time_val_rd(23 downto 16);
            elsif ADDR_IN = X"12" then
                DATA_OUT <= time_val_rd(15 downto 8);
            elsif ADDR_IN = X"13" then
                DATA_OUT <= time_val_rd(7 downto 0);
            elsif ADDR_IN = X"14" then
                DATA_OUT <= is_locked_rd;
            elsif ADDR_IN = X"15" then
                DATA_OUT <= X"0"&num_satellites_count_rd;
            elsif ADDR_IN = X"16" then
                DATA_OUT <= num_satellites_rd(15 downto 8);
            elsif ADDR_IN = X"17" then
                DATA_OUT <= num_satellites_rd(7 downto 0);
            elsif ADDR_IN = X"18" then
                DATA_OUT <= utc_rd(47 downto 40);
            elsif ADDR_IN = X"19" then
                DATA_OUT <= utc_rd(39 downto 32);
            elsif ADDR_IN = X"1A" then
                DATA_OUT <= utc_rd(31 downto 24);
            elsif ADDR_IN = X"1B" then
                DATA_OUT <= utc_rd(23 downto 16);
            elsif ADDR_IN = X"1C" then
                DATA_OUT <= utc_rd(15 downto 8);
            elsif ADDR_IN = X"1D" then
                DATA_OUT <= utc_rd(7 downto 0);
            elsif ADDR_IN = X"1E" then
                DATA_OUT <= day_rd(15 downto 8);
            elsif ADDR_IN = X"1F" then
                DATA_OUT <= day_rd(7 downto 0);
            elsif ADDR_IN = X"20" then
                DATA_OUT <= month_rd(15 downto 8);
            elsif ADDR_IN = X"21" then
                DATA_OUT <= month_rd(7 downto 0);
            elsif ADDR_IN = X"22" then
                DATA_OUT <= year_rd(31 downto 24);
            elsif ADDR_IN = X"23" then
                DATA_OUT <= year_rd(23 downto 16);
            elsif ADDR_IN = X"24" then
                DATA_OUT <= year_rd(15 downto 8);
            elsif ADDR_IN = X"25" then
                DATA_OUT <= year_rd(7 downto 0);
            elsif ADDR_IN = X"26" then
                DATA_OUT <= local_zone_rd(15 downto 8);
            elsif ADDR_IN = X"27" then
                DATA_OUT <= local_zone_rd(7 downto 0);
            end if;
        end if;
    end process;

end Behavioral;