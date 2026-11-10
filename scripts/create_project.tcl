# =====================================================================
# 포트리스 Vivado 프로젝트 자동 생성 스크립트
#
# 쓰는 법 (Vivado 첫 화면 아래쪽 Tcl Console 에 입력):
#     cd C:/Users/내이름/fortress-fpga        (레포를 받은 폴더. 경로 구분은 / 로)
#     source scripts/create_project.tcl
#
# 하는 일
#   - 레포 안 vivado/ 폴더에 프로젝트 fortress 를 만들어요 (보드 칩: xc7s75fgga484-1)
#   - rtl/ 소스, rtl/include 헤더, rom/*.mem, 핀 제약, 테스트벤치를 전부 추가해요
#   - include 경로, Top 모듈, 시뮬레이션 실행 시간까지 설정해요
# 이미 vivado/ 폴더가 있으면 지우고 새로 만들어요 (-force). 소스 파일은 건드리지 않아요.
# =====================================================================

set root [file normalize [file join [file dirname [info script]] ..]]
set part xc7s75fgga484-1

create_project fortress [file join $root vivado] -part $part -force

# ---- 설계 소스 (.v), 헤더 (.vh), ROM 초기화 파일 (.mem)
add_files -fileset sources_1 [glob [file join $root rtl *.v] [file join $root rtl * *.v]]
add_files -fileset sources_1 [glob [file join $root rtl include *.vh]]
add_files -fileset sources_1 [glob [file join $root rom *.mem]]
set_property include_dirs [file join $root rtl include] [get_filesets sources_1]
set_property top fortress_top [get_filesets sources_1]

# ---- 핀 제약
add_files -fileset constrs_1 [file join $root constraints fortress.xdc]

# ---- 시뮬레이션 (테스트벤치 2개, 기본은 tb_trajectory)
add_files -fileset sim_1 [glob [file join $root sim *.v]]
set_property include_dirs [file join $root rtl include] [get_filesets sim_1]
set_property top tb_trajectory [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
# 기본 1000 ns 에서 멈추지 않고 테스트벤치가 $finish 할 때까지 돌게 함
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "============================================================"
puts " 포트리스 프로젝트를 만들었어요: [file join $root vivado fortress.xpr]"
puts " 다음: 왼쪽 Flow Navigator > SIMULATION > Run Simulation > Run Behavioral Simulation"
puts "       Tcl Console 에 'PASS: all 104 vectors match' 가 나오면 탄도 회로 정상"
puts "============================================================"
