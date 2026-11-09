## =====================================================================
## 포트리스 핀 제약 (Combo II-DLD, Xilinx Spartan-7)  - LCDL/Xilinx_S7_Pin_Map.xlsx 기준
## 최상위 모듈: fortress_top
## ※ 클럭 핀은 수업 실습에서 쓰던 핀으로 꼭 확인하세요 (아래는 FPGA_CLK1 = B6).
##   보드 클럭 스위치를 1 MHz로 두세요. 다른 주파수면 fortress_top 의 CLK_HZ 도 바꿔야 해요.
## =====================================================================

## ---- 클럭 (1 MHz)
set_property -dict { PACKAGE_PIN B6  IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -name sys_clk -period 1000.000 [get_ports clk]

## ---- 키패드 버튼 KEY01..KEY12 = 1 2 3 / 4 5 6 / 7 8 9 / * 0 #
set_property -dict { PACKAGE_PIN K4  IOSTANDARD LVCMOS33 } [get_ports {key[0]}]
set_property -dict { PACKAGE_PIN N8  IOSTANDARD LVCMOS33 } [get_ports {key[1]}]
set_property -dict { PACKAGE_PIN N4  IOSTANDARD LVCMOS33 } [get_ports {key[2]}]
set_property -dict { PACKAGE_PIN N1  IOSTANDARD LVCMOS33 } [get_ports {key[3]}]
set_property -dict { PACKAGE_PIN P6  IOSTANDARD LVCMOS33 } [get_ports {key[4]}]
set_property -dict { PACKAGE_PIN N6  IOSTANDARD LVCMOS33 } [get_ports {key[5]}]
set_property -dict { PACKAGE_PIN L5  IOSTANDARD LVCMOS33 } [get_ports {key[6]}]
set_property -dict { PACKAGE_PIN J2  IOSTANDARD LVCMOS33 } [get_ports {key[7]}]
set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 } [get_ports {key[8]}]
set_property -dict { PACKAGE_PIN L7  IOSTANDARD LVCMOS33 } [get_ports {key[9]}]
set_property -dict { PACKAGE_PIN L1  IOSTANDARD LVCMOS33 } [get_ports {key[10]}]
set_property -dict { PACKAGE_PIN K6  IOSTANDARD LVCMOS33 } [get_ports {key[11]}]

## ---- DIP 스위치 1..8
set_property -dict { PACKAGE_PIN Y1  IOSTANDARD LVCMOS33 } [get_ports {dip[0]}]
set_property -dict { PACKAGE_PIN W3  IOSTANDARD LVCMOS33 } [get_ports {dip[1]}]
set_property -dict { PACKAGE_PIN U2  IOSTANDARD LVCMOS33 } [get_ports {dip[2]}]
set_property -dict { PACKAGE_PIN T1  IOSTANDARD LVCMOS33 } [get_ports {dip[3]}]
set_property -dict { PACKAGE_PIN W4  IOSTANDARD LVCMOS33 } [get_ports {dip[4]}]
set_property -dict { PACKAGE_PIN W1  IOSTANDARD LVCMOS33 } [get_ports {dip[5]}]
set_property -dict { PACKAGE_PIN V4  IOSTANDARD LVCMOS33 } [get_ports {dip[6]}]
set_property -dict { PACKAGE_PIN U4  IOSTANDARD LVCMOS33 } [get_ports {dip[7]}]

## ---- LED 8개
set_property -dict { PACKAGE_PIN L4  IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN M4  IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN M2  IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN N7  IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN M7  IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN M3  IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN M1  IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN N5  IOSTANDARD LVCMOS33 } [get_ports {led[7]}]

## ---- 1자리 7세그 (포탄 번호) seg1_data = {a,b,c,d,e,f,g,dp}
set_property -dict { PACKAGE_PIN P1  IOSTANDARD LVCMOS33 } [get_ports {seg1_data[7]}]
set_property -dict { PACKAGE_PIN P3  IOSTANDARD LVCMOS33 } [get_ports {seg1_data[6]}]
set_property -dict { PACKAGE_PIN P7  IOSTANDARD LVCMOS33 } [get_ports {seg1_data[5]}]
set_property -dict { PACKAGE_PIN N3  IOSTANDARD LVCMOS33 } [get_ports {seg1_data[4]}]
set_property -dict { PACKAGE_PIN T5  IOSTANDARD LVCMOS33 } [get_ports {seg1_data[3]}]
set_property -dict { PACKAGE_PIN R2  IOSTANDARD LVCMOS33 } [get_ports {seg1_data[2]}]
set_property -dict { PACKAGE_PIN R4  IOSTANDARD LVCMOS33 } [get_ports {seg1_data[1]}]
set_property -dict { PACKAGE_PIN R6  IOSTANDARD LVCMOS33 } [get_ports {seg1_data[0]}]

## ---- 8자리 7세그 seg_data = {a,b,c,d,e,f,g,dp}, seg_com[0..7] = AR_SEG_S0..S7
set_property -dict { PACKAGE_PIN F1  IOSTANDARD LVCMOS33 } [get_ports {seg_data[7]}]
set_property -dict { PACKAGE_PIN F5  IOSTANDARD LVCMOS33 } [get_ports {seg_data[6]}]
set_property -dict { PACKAGE_PIN E2  IOSTANDARD LVCMOS33 } [get_ports {seg_data[5]}]
set_property -dict { PACKAGE_PIN E4  IOSTANDARD LVCMOS33 } [get_ports {seg_data[4]}]
set_property -dict { PACKAGE_PIN J1  IOSTANDARD LVCMOS33 } [get_ports {seg_data[3]}]
set_property -dict { PACKAGE_PIN J3  IOSTANDARD LVCMOS33 } [get_ports {seg_data[2]}]
set_property -dict { PACKAGE_PIN J7  IOSTANDARD LVCMOS33 } [get_ports {seg_data[1]}]
set_property -dict { PACKAGE_PIN H2  IOSTANDARD LVCMOS33 } [get_ports {seg_data[0]}]
set_property -dict { PACKAGE_PIN H4  IOSTANDARD LVCMOS33 } [get_ports {seg_com[0]}]
set_property -dict { PACKAGE_PIN H6  IOSTANDARD LVCMOS33 } [get_ports {seg_com[1]}]
set_property -dict { PACKAGE_PIN G1  IOSTANDARD LVCMOS33 } [get_ports {seg_com[2]}]
set_property -dict { PACKAGE_PIN G3  IOSTANDARD LVCMOS33 } [get_ports {seg_com[3]}]
set_property -dict { PACKAGE_PIN L6  IOSTANDARD LVCMOS33 } [get_ports {seg_com[4]}]
set_property -dict { PACKAGE_PIN K1  IOSTANDARD LVCMOS33 } [get_ports {seg_com[5]}]
set_property -dict { PACKAGE_PIN K3  IOSTANDARD LVCMOS33 } [get_ports {seg_com[6]}]
set_property -dict { PACKAGE_PIN K5  IOSTANDARD LVCMOS33 } [get_ports {seg_com[7]}]

## ---- Full color LED 4개 (rgb_x[0] = F_LED1)
set_property -dict { PACKAGE_PIN T2  IOSTANDARD LVCMOS33 } [get_ports {rgb_r[0]}]
set_property -dict { PACKAGE_PIN U1  IOSTANDARD LVCMOS33 } [get_ports {rgb_r[1]}]
set_property -dict { PACKAGE_PIN P2  IOSTANDARD LVCMOS33 } [get_ports {rgb_r[2]}]
set_property -dict { PACKAGE_PIN R3  IOSTANDARD LVCMOS33 } [get_ports {rgb_r[3]}]
set_property -dict { PACKAGE_PIN U5  IOSTANDARD LVCMOS33 } [get_ports {rgb_g[0]}]
set_property -dict { PACKAGE_PIN V1  IOSTANDARD LVCMOS33 } [get_ports {rgb_g[1]}]
set_property -dict { PACKAGE_PIN R7  IOSTANDARD LVCMOS33 } [get_ports {rgb_g[2]}]
set_property -dict { PACKAGE_PIN T6  IOSTANDARD LVCMOS33 } [get_ports {rgb_g[3]}]
set_property -dict { PACKAGE_PIN U3  IOSTANDARD LVCMOS33 } [get_ports {rgb_b[0]}]
set_property -dict { PACKAGE_PIN W2  IOSTANDARD LVCMOS33 } [get_ports {rgb_b[1]}]
set_property -dict { PACKAGE_PIN R5  IOSTANDARD LVCMOS33 } [get_ports {rgb_b[2]}]
set_property -dict { PACKAGE_PIN T3  IOSTANDARD LVCMOS33 } [get_ports {rgb_b[3]}]

## ---- Text LCD
set_property -dict { PACKAGE_PIN A4  IOSTANDARD LVCMOS33 } [get_ports {lcd_data[0]}]
set_property -dict { PACKAGE_PIN B2  IOSTANDARD LVCMOS33 } [get_ports {lcd_data[1]}]
set_property -dict { PACKAGE_PIN C3  IOSTANDARD LVCMOS33 } [get_ports {lcd_data[2]}]
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports {lcd_data[3]}]
set_property -dict { PACKAGE_PIN A2  IOSTANDARD LVCMOS33 } [get_ports {lcd_data[4]}]
set_property -dict { PACKAGE_PIN C5  IOSTANDARD LVCMOS33 } [get_ports {lcd_data[5]}]
set_property -dict { PACKAGE_PIN C1  IOSTANDARD LVCMOS33 } [get_ports {lcd_data[6]}]
set_property -dict { PACKAGE_PIN D1  IOSTANDARD LVCMOS33 } [get_ports {lcd_data[7]}]
set_property -dict { PACKAGE_PIN A6  IOSTANDARD LVCMOS33 } [get_ports lcd_e]
set_property -dict { PACKAGE_PIN G6  IOSTANDARD LVCMOS33 } [get_ports lcd_rs]
set_property -dict { PACKAGE_PIN D6  IOSTANDARD LVCMOS33 } [get_ports lcd_rw]

## ---- Piezo / 서보 / 스텝모터 (step_coil = {A, B, /A, /B})
set_property -dict { PACKAGE_PIN Y21  IOSTANDARD LVCMOS33 } [get_ports piezo]
set_property -dict { PACKAGE_PIN AA22 IOSTANDARD LVCMOS33 } [get_ports servo]
set_property -dict { PACKAGE_PIN Y19  IOSTANDARD LVCMOS33 } [get_ports step_sensor]
set_property -dict { PACKAGE_PIN Y20  IOSTANDARD LVCMOS33 } [get_ports {step_coil[3]}]
set_property -dict { PACKAGE_PIN Y22  IOSTANDARD LVCMOS33 } [get_ports {step_coil[2]}]
set_property -dict { PACKAGE_PIN AA20 IOSTANDARD LVCMOS33 } [get_ports {step_coil[1]}]
set_property -dict { PACKAGE_PIN AA21 IOSTANDARD LVCMOS33 } [get_ports {step_coil[0]}]
