library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity nmea_parser is
    port (  
            CLK_IN          : IN  STD_LOGIC;
            RST_IN          : IN  STD_LOGIC; 
            
            NMEA_EN_IN      : IN  STD_LOGIC;
            NMEA_DATA_IN    : IN  STD_LOGIC_VECTOR(7 downto 0);

            ADDR_IN         : IN  STD_LOGIC_VECTOR(7 downto 0);
            DATA_OUT        : OUT  STD_LOGIC_VECTOR(7 downto 0));
end nmea_parser;

architecture Behavioral of nmea_parser is

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

constant C_start_sentence_delimiter : std_logic_vector(7 downto 0) := to_slv("$");

constant C_GP       : std_logic_vector(15 downto 0) := to_slv("GP");
constant C_GPVTG    : std_logic_vector(39 downto 0) := to_slv("GPVTG");
constant C_GPGGA    : std_logic_vector(39 downto 0) := to_slv("GPGGA");
constant C_GPRMC    : std_logic_vector(39 downto 0) := to_slv("GPRMC");
constant C_GPGSA    : std_logic_vector(39 downto 0) := to_slv("GPGSA");
constant C_GPGSV    : std_logic_vector(39 downto 0) := to_slv("GPGSV");

signal nmea_en_prev, nmea_en                        : std_logic := '0';
signal nmea_data_ini_ini, nmea_data_ini, nmea_data  : std_logic_vector(7 downto 0) := (others => '0');
signal nmea_data_valid                              : std_logic := '0';

signal nmea_tag_val                                 : std_logic_vector(23 downto 0) := (others => '0');

type NMEA_PARSE_STATE is (
                            IDLE,
                            RECEIVED_START_DELIM,
                            RECEIVED_START_OF_TAG,
                            COLLECT_TAG_VAL0,
                            COLLECT_TAG_VAL1,
                            COLLECT_TAG_VAL2,
                            PARSE_TAG_VAL,
                            PARSE_GPVTG_SENTENCE0,

                            PARSE_GPGGA_SENTENCE0,

                            PARSE_GPRMC_SENTENCE0,

                            PARSE_GPGSA_SENTENCE0,

                            PARSE_GPGSV_SENTENCE0,

                            COMPLETE
                        );

signal np_st, np_st_next : NMEA_PARSE_STATE := IDLE;

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

    NMEA_PARSE_STATE_NEXT: process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            np_st <= np_st_next;
        end if;
    end process;

    MAIN_STATE_DECODE: process (np_st, nmea_data_valid, nmea_data)
    begin
        np_st_next <= np_st; -- default to remain in same state
        case (np_st) is
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
                else
                    np_st_next <= COMPLETE;
                end if;

            when PARSE_GPVTG_SENTENCE0 =>
                np_st_next <= COMPLETE;

            when PARSE_GPGGA_SENTENCE0 =>
                np_st_next <= COMPLETE;

            when PARSE_GPRMC_SENTENCE0 =>
                np_st_next <= COMPLETE;

            when PARSE_GPGSA_SENTENCE0 =>
                np_st_next <= COMPLETE;

            when PARSE_GPGSV_SENTENCE0 =>
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

end Behavioral;