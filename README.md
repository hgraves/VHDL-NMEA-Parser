# VHDL NMEA
VHDL Module which parses a NMEA 0183 stream  
Also displays captured data on 16x2 LCD display (standard LCD interface)

### Example NMEA Stream
```
$GPRMC,002454,A,3553.5295,N,13938.6570,E,0.0,43.1,180700,7.1,W,A*3F
$GPRMB,A,,,,,,,,,,,,A,A*0B
$GPGGA,002454,3553.5295,N,13938.6570,E,1,05,2.2,18.3,M,39.0,M,,*7F
$GPGSA,A,3,01,04,07,16,20,,,,,,,,3.6,2.2,2.7*35
$GPGSV,3,1,09,01,38,103,37,02,23,215,00,04,38,297,37,05,00,328,00*70
$GPGSV,3,2,09,07,77,299,47,11,07,087,00,16,74,041,47,20,38,044,43*73
$GPGSV,3,3,09,24,12,282,00*4D
$GPGLL,3553.5295,N,13938.6570,E,002454,A,A*4F
$GPBOD,,T,,M,,*47
$PGRME,8.6,M,9.6,M,12.9,M*15
$PGRMZ,51,f*30
$HCHDG,101.1,,,7.1,W*3C
$GPRTE,1,1,c,*37
$GPRMC,002456,A,3553.5295,N,13938.6570,E,0.0,43.1,180700,7.1,W,A*3D
$GPZDA,054201.000,11,02,2016,,*53
```

### Notes
The GPZDA sentence (required for UTC timestamp) is disabled by default in some GPS modules. The NMEA parser enables 
it upon startup by sending a vendor specific enabling sentence. This sentence is defined in 'coe_dir/SIRF_3_GPS.configure':

```
24 # $
50 # P
53 # S
52 # R
46 # F
31 # 1
30 # 0
33 # 3
2c # ,
30 # 0
38 # 8
2c # ,
30 # 0
30 # 0
2c # ,
30 # 0
31 # 1
2c # ,
30 # 0
31 # 1
2a # *
32 # 2
44 # D
0d # CR
0a # LF
FF # END
```
If you need to change this sentence (i.e. you are not using a SIRF GPS module) you are required to rebuild the  
binary coe file ('SIRF_3_GPS.coe'). This is done via:
```
$ gcc coe_file_gen.c -o coe_file_gen
$ ./coe_file_gen SIRF_3_GPS.configure SIRF_3_GPS.coe
Writing data to coe file..97 %
Complete
```

### Outputs
Currently the NMEA Parser captures the following:  
- Velocity
- Local Time
- Locked status
- Number of satellites locked
- UTC Time

It also converts the UTC time into unix epoch time.

### Display Outputs

### Information
Information on NMEA 0183 is available [here](http://aprs.gids.nl/nmea/) and [here](http://www.gpsinformation.org/dale/nmea.htm)
