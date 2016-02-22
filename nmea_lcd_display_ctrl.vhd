library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity nmea_lcd_display_ctrl is
	generic (
    	SECONDS_BETWEEN_DISPLAY_SHIFT 	: positive := 4;
    	CLK_IN_FREQUENCY_MHZ 		 	: positive := 100);
    port (  
            CLK_IN          : IN  STD_LOGIC;
            RST_IN          : IN  STD_LOGIC;

            ADDR_OUT        : OUT  STD_LOGIC_VECTOR(7 downto 0);
            DATA_IN        	: IN STD_LOGIC_VECTOR(7 downto 0);

            LINE1_OUT 		: OUT STD_LOGIC_VECTOR(127 downto 0);
            LINE2_OUT 		: OUT STD_LOGIC_VECTOR(127 downto 0));
end nmea_lcd_display_ctrl;

architecture Behavioral of nmea_lcd_display_ctrl is

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

constant C_tick_count 						: std_logic_vector(31 downto 0) := slv(to_unsigned((CLK_IN_FREQUENCY_MHZ*1000000) - 1, 32));
--constant C_tick_count 						: std_logic_vector(31 downto 0) := slv(to_unsigned((CLK_IN_FREQUENCY_MHZ*1000) - 1, 32)); -- FOR TESTING
constant C_update_counter 					: std_logic_vector(7 downto 0) := slv(to_unsigned(SECONDS_BETWEEN_DISPLAY_SHIFT - 1, 8));

signal tick_count 							: unsigned(31 downto 0) := unsigned(C_tick_count);
signal once_per_second_tick 				: std_logic := '0';
signal update_counter 						: unsigned(7 downto 0) := unsigned(C_update_counter);
signal do_screen_update 					: std_logic := '0';
signal is_locked 							: std_logic_vector(7 downto 0) := (others => '0');
signal num_satellites_chars 				: std_logic_vector(3 downto 0) := (others => '0');

signal locked_line 							: std_logic_vector(127 downto 0) := to_slv("Locked: False   ");
signal satellites_line 						: std_logic_vector(127 downto 0) := to_slv("Satellites: 0   ");
signal time_line 							: std_logic_vector(127 downto 0) := to_slv("Time: 00:00:00  ");
signal velocity_line 						: std_logic_vector(127 downto 0) := to_slv("Speed: 0.0 KM/H ");
signal shift_line 							: std_logic_vector(127 downto 0) := to_slv("                ");
signal utc_line 							: std_logic_vector(127 downto 0) := to_slv("UTC:  00:00:00  ");
signal date_line 							: std_logic_vector(127 downto 0) := to_slv("Date: 00:00:0000");

signal addr 								: unsigned(7 downto 0) := (others => '0');
signal second_line_disp						: unsigned(1 downto 0) := (others => '0');

type UPDATE_ST is (
                            IDLE,
                            UPDATE_LOCKED_LINE0,
                            UPDATE_LOCKED_LINE1,
                            UPDATE_LOCKED_LINE2,
                            UPDATE_LOCKED_LINE3,
                            UPDATE_LOCKED_LINE4,
                            UPDATE_LOCKED_LINE5,
                            UPDATE_LOCKED_LINE6,
                            UPDATE_LOCKED_LINE7,
                            UPDATE_TIME_LINE0,
                            UPDATE_TIME_LINE1,
                            UPDATE_TIME_LINE2,
                            UPDATE_TIME_LINE3,
                            UPDATE_TIME_LINE4,
                            UPDATE_TIME_LINE5,
                            UPDATE_TIME_LINE6,
                            UPDATE_TIME_LINE7,
                            UPDATE_SATELLITES_LINE0,
                            UPDATE_SATELLITES_LINE1,
                            UPDATE_SATELLITES_LINE2,
                            UPDATE_SATELLITES_LINE3,
                            UPDATE_SATELLITES_LINE4,
                            UPDATE_UTC_TIME_LINE0,
                            UPDATE_UTC_TIME_LINE1,
                            UPDATE_UTC_TIME_LINE2,
                            UPDATE_UTC_TIME_LINE3,
                            UPDATE_UTC_TIME_LINE4,
                            UPDATE_UTC_TIME_LINE5,
                            UPDATE_UTC_TIME_LINE6,
                            UPDATE_UTC_TIME_LINE7,
                            UPDATE_UTC_DATE_LINE0,
                            UPDATE_UTC_DATE_LINE1,
                            UPDATE_UTC_DATE_LINE2,
                            UPDATE_UTC_DATE_LINE3,
                            UPDATE_UTC_DATE_LINE4,
                            UPDATE_UTC_DATE_LINE5,
                            UPDATE_UTC_DATE_LINE6,
                            UPDATE_UTC_DATE_LINE7,
                            UPDATE_UTC_DATE_LINE8,
                            UPDATE_UTC_DATE_LINE9,
                            UPDATE_SPEED_LINE0,
                            SET_SHIFT_LINE0,
                            COMPLETE
                        );

signal up_st, up_st_next : UPDATE_ST := IDLE;

begin

	LINE1_OUT <= time_line;
	LINE2_OUT <= shift_line;
	ADDR_OUT <= slv(addr);

	REFRESH_SCREEN: process(CLK_IN)
	begin
		if rising_edge(CLK_IN) then
			if tick_count = X"00000000" then
				tick_count <= unsigned(C_tick_count);
			else
				tick_count <= tick_count - 1;
			end if;
			if tick_count = X"00000000" then
				once_per_second_tick <= '1';
			else
				once_per_second_tick <= '0';
			end if;
			if once_per_second_tick = '1' then
				if update_counter = X"00" then
					update_counter <= unsigned(C_update_counter);
				else
					update_counter <= update_counter - 1;
				end if;
			end if;
			if update_counter = X"00" and once_per_second_tick = '1' then
				do_screen_update <= '1';
			elsif up_st = SET_SHIFT_LINE0 then
				do_screen_update <= '0';
			end if;
		end if;
	end process;

	UPDATE_FSM: process(CLK_IN)
	begin
		if rising_edge(CLK_IN) then
			up_st <= up_st_next;
		end if;
	end process;

	MAIN_STATE_DECODE: process (up_st, once_per_second_tick, do_screen_update)
    begin
        up_st_next <= up_st; -- default to remain in same state
        case (up_st) is
            when IDLE =>
            	if once_per_second_tick = '1' then
            		up_st_next <= UPDATE_LOCKED_LINE0;
            	end if;
            when UPDATE_LOCKED_LINE0 =>
            	up_st_next <= UPDATE_LOCKED_LINE1;
            when UPDATE_LOCKED_LINE1 =>
            	up_st_next <= UPDATE_LOCKED_LINE2;
            when UPDATE_LOCKED_LINE2 =>
            	up_st_next <= UPDATE_LOCKED_LINE3;
            when UPDATE_LOCKED_LINE3 =>
            	up_st_next <= UPDATE_LOCKED_LINE4;
            when UPDATE_LOCKED_LINE4 =>
            	up_st_next <= UPDATE_LOCKED_LINE5;
            when UPDATE_LOCKED_LINE5 =>
            	up_st_next <= UPDATE_LOCKED_LINE6;
            when UPDATE_LOCKED_LINE6 =>
            	up_st_next <= UPDATE_LOCKED_LINE7;
            when UPDATE_LOCKED_LINE7 =>
            	up_st_next <= UPDATE_TIME_LINE0;
            when UPDATE_TIME_LINE0 =>
            	up_st_next <= UPDATE_TIME_LINE1;
            when UPDATE_TIME_LINE1 =>
            	up_st_next <= UPDATE_TIME_LINE2;
            when UPDATE_TIME_LINE2 =>
            	up_st_next <= UPDATE_TIME_LINE3;
            when UPDATE_TIME_LINE3 =>
            	up_st_next <= UPDATE_TIME_LINE4;
            when UPDATE_TIME_LINE4 =>
            	up_st_next <= UPDATE_TIME_LINE5;
            when UPDATE_TIME_LINE5 =>
            	up_st_next <= UPDATE_TIME_LINE6;
            when UPDATE_TIME_LINE6 =>
            	up_st_next <= UPDATE_TIME_LINE7;
            when UPDATE_TIME_LINE7 =>
            	up_st_next <= UPDATE_SATELLITES_LINE0;
            when UPDATE_SATELLITES_LINE0 =>
            	up_st_next <= UPDATE_SATELLITES_LINE1;
            when UPDATE_SATELLITES_LINE1 =>
            	up_st_next <= UPDATE_SATELLITES_LINE2;
            when UPDATE_SATELLITES_LINE2 =>
            	up_st_next <= UPDATE_SATELLITES_LINE3;
            when UPDATE_SATELLITES_LINE3 =>
            	up_st_next <= UPDATE_SATELLITES_LINE4;
            when UPDATE_SATELLITES_LINE4 =>
            	up_st_next <= UPDATE_UTC_TIME_LINE0;
            when UPDATE_UTC_TIME_LINE0 =>
            	up_st_next <= UPDATE_UTC_TIME_LINE1;
            when UPDATE_UTC_TIME_LINE1 =>
            	up_st_next <= UPDATE_UTC_TIME_LINE2;
            when UPDATE_UTC_TIME_LINE2 =>
            	up_st_next <= UPDATE_UTC_TIME_LINE3;
            when UPDATE_UTC_TIME_LINE3 =>
            	up_st_next <= UPDATE_UTC_TIME_LINE4;
            when UPDATE_UTC_TIME_LINE4 =>
            	up_st_next <= UPDATE_UTC_TIME_LINE5;
            when UPDATE_UTC_TIME_LINE5 =>
            	up_st_next <= UPDATE_UTC_TIME_LINE6;
            when UPDATE_UTC_TIME_LINE6 =>
            	up_st_next <= UPDATE_UTC_TIME_LINE7;
            when UPDATE_UTC_TIME_LINE7 =>
            	up_st_next <= UPDATE_UTC_DATE_LINE0;
            when UPDATE_UTC_DATE_LINE0 =>
            	up_st_next <= UPDATE_UTC_DATE_LINE1;
            when UPDATE_UTC_DATE_LINE1 =>
            	up_st_next <= UPDATE_UTC_DATE_LINE2;
            when UPDATE_UTC_DATE_LINE2 =>
            	up_st_next <= UPDATE_UTC_DATE_LINE3;
            when UPDATE_UTC_DATE_LINE3 =>
            	up_st_next <= UPDATE_UTC_DATE_LINE4;
            when UPDATE_UTC_DATE_LINE4 =>
            	up_st_next <= UPDATE_UTC_DATE_LINE5;
            when UPDATE_UTC_DATE_LINE5 =>
            	up_st_next <= UPDATE_UTC_DATE_LINE6;
            when UPDATE_UTC_DATE_LINE6 =>
            	up_st_next <= UPDATE_UTC_DATE_LINE7;
            when UPDATE_UTC_DATE_LINE7 =>
            	up_st_next <= UPDATE_UTC_DATE_LINE8;
            when UPDATE_UTC_DATE_LINE8 =>
            	up_st_next <= UPDATE_UTC_DATE_LINE9;
            when UPDATE_UTC_DATE_LINE9 =>
            	up_st_next <= UPDATE_SPEED_LINE0;

            when UPDATE_SPEED_LINE0 => -- TODO
            	if do_screen_update = '1' then
            		up_st_next <= SET_SHIFT_LINE0;
            	else
            		up_st_next <= COMPLETE;
            	end if;

            when SET_SHIFT_LINE0 =>
            	up_st_next <= COMPLETE;

            when COMPLETE =>
            	up_st_next <= IDLE;
        end case;
    end process;

    SET_ADDR_OUT: process(CLK_IN)
	begin
		if rising_edge(CLK_IN) then
			if up_st /= IDLE then
				if up_st = UPDATE_LOCKED_LINE0 then
					addr <= X"14";
				elsif up_st = UPDATE_TIME_LINE0 then
					addr <= X"0E";
				elsif up_st = UPDATE_SATELLITES_LINE0 then
					addr <= X"15";
				elsif up_st = UPDATE_UTC_TIME_LINE0 then
					addr <= X"18";
				elsif up_st = UPDATE_UTC_DATE_LINE0 then
					addr <= X"1E";
				elsif up_st = UPDATE_SPEED_LINE0 then
					addr <= X"00";
				else 
					addr <= addr + 1;
				end if;
			end if;
		end if;
	end process;

	SET_IS_LOCKED_LINE: process(CLK_IN)
	begin
		if rising_edge(CLK_IN) then
			if up_st = UPDATE_LOCKED_LINE2 then
				is_locked <= DATA_IN;
			end if;
			if up_st = UPDATE_LOCKED_LINE3 then
				if is_locked /= X"31" then
					locked_line(63 downto 56) <= to_slv("F");
				else
					locked_line(63 downto 56) <= to_slv("T");		
				end if;	
			end if;
			if up_st = UPDATE_LOCKED_LINE4 then
				if is_locked /= X"31" then
					locked_line(55 downto 48) <= to_slv("a");
				else
					locked_line(55 downto 48) <= to_slv("r");		
				end if;	
			end if;
			if up_st = UPDATE_LOCKED_LINE5 then
				if is_locked /= X"31" then
					locked_line(47 downto 40) <= to_slv("l");
				else
					locked_line(47 downto 40) <= to_slv("u");		
				end if;	
			end if;
			if up_st = UPDATE_LOCKED_LINE6 then
				if is_locked /= X"31" then
					locked_line(39 downto 32) <= to_slv("s");
				else
					locked_line(39 downto 32) <= to_slv("e");		
				end if;	
			end if;
			if up_st = UPDATE_LOCKED_LINE7 then
				if is_locked /= X"31" then
					locked_line(31 downto 24) <= to_slv("e");
				else
					locked_line(31 downto 24) <= to_slv(" ");		
				end if;	
			end if;
		end if;
	end process;

	SET_TIME_LINE: process(CLK_IN)
	begin
		if rising_edge(CLK_IN) then
			if up_st = UPDATE_TIME_LINE2 then
				time_line(79 downto 72) <= DATA_IN;
			end if;
			if up_st = UPDATE_TIME_LINE3 then
				time_line(71 downto 64) <= DATA_IN;
			end if;
			if up_st = UPDATE_TIME_LINE4 then
				time_line(55 downto 48) <= DATA_IN;
			end if;
			if up_st = UPDATE_TIME_LINE5 then
				time_line(47 downto 40) <= DATA_IN;
			end if;
			if up_st = UPDATE_TIME_LINE6 then
				time_line(31 downto 24) <= DATA_IN;
			end if;
			if up_st = UPDATE_TIME_LINE7 then
				time_line(23 downto 16) <= DATA_IN;
			end if;
		end if;
	end process;

	SET_SATELLITES_LINE: process(CLK_IN)
	begin
		if rising_edge(CLK_IN) then
			if up_st = UPDATE_SATELLITES_LINE2 then
				num_satellites_chars <= DATA_IN(3 downto 0);
			end if;
			if up_st = UPDATE_SATELLITES_LINE3 then
				satellites_line(31 downto 24) <= DATA_IN;
			end if;
			if up_st = UPDATE_SATELLITES_LINE4 then
				if num_satellites_chars = X"1" then
					satellites_line(23 downto 16) <= to_slv(" ");
				else
					satellites_line(23 downto 16) <= DATA_IN;
				end if;
			end if;
		end if;
	end process;

	SET_UTC_LINE: process(CLK_IN)
	begin
		if rising_edge(CLK_IN) then
			if up_st = UPDATE_UTC_TIME_LINE2 then
				utc_line(79 downto 72) <= DATA_IN;
			end if;
			if up_st = UPDATE_UTC_TIME_LINE3 then
				utc_line(71 downto 64) <= DATA_IN;
			end if;
			if up_st = UPDATE_UTC_TIME_LINE4 then
				utc_line(55 downto 48) <= DATA_IN;
			end if;
			if up_st = UPDATE_UTC_TIME_LINE5 then
				utc_line(47 downto 40) <= DATA_IN;
			end if;
			if up_st = UPDATE_UTC_TIME_LINE6 then
				utc_line(31 downto 24) <= DATA_IN;
			end if;
			if up_st = UPDATE_UTC_TIME_LINE7 then
				utc_line(23 downto 16) <= DATA_IN;
			end if;
		end if;
	end process;

	SET_DATE_LINE: process(CLK_IN)
	begin
		if rising_edge(CLK_IN) then
			if up_st = UPDATE_UTC_DATE_LINE2 then
				date_line(79 downto 72) <= DATA_IN;
			end if;
			if up_st = UPDATE_UTC_DATE_LINE3 then
				date_line(71 downto 64) <= DATA_IN;
			end if;
			if up_st = UPDATE_UTC_DATE_LINE4 then
				date_line(55 downto 48) <= DATA_IN;
			end if;
			if up_st = UPDATE_UTC_DATE_LINE5 then
				date_line(47 downto 40) <= DATA_IN;
			end if;
			if up_st = UPDATE_UTC_DATE_LINE6 then
				date_line(31 downto 24) <= DATA_IN;
			end if;
			if up_st = UPDATE_UTC_DATE_LINE7 then
				date_line(23 downto 16) <= DATA_IN;
			end if;
			if up_st = UPDATE_UTC_DATE_LINE8 then
				date_line(15 downto 8) <= DATA_IN;
			end if;
			if up_st = UPDATE_UTC_DATE_LINE9 then
				date_line(7 downto 0) <= DATA_IN;
			end if;
		end if;
	end process;

--	SET_SPEED_LINE: process(CLK_IN) -- TODO
--	begin
--		if rising_edge(CLK_IN) then
--
--		end if;
--	end process;

	SET_DISPLAY_LINE2: process(CLK_IN)
	begin
		if rising_edge(CLK_IN) then
			if up_st = SET_SHIFT_LINE0 then
				second_line_disp <= second_line_disp + 1;
			end if;
			if up_st = SET_SHIFT_LINE0 then
				if second_line_disp = "00" then
					shift_line <= satellites_line;
				elsif second_line_disp = "01" then
					shift_line <= locked_line;
				elsif second_line_disp = "10" then
					shift_line <= utc_line;
				elsif second_line_disp = "11" then
					shift_line <= date_line;
				end if;
			end if;
		end if;
	end process;

end Behavioral;