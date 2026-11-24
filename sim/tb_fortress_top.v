`timescale 1ns/1ps
// =====================================================================
// fortress_top 통합 시뮬레이션 (1 MHz 클럭, 실제 시간으로 몇 초 분량)
//   - 5를 눌러 설정 화면 -> 5를 한 번 더 눌러 게임 시작 -> 첫 턴 이동만 (P1, P2 둘 다 5로 넘김)
//   - P1: 각도 몇 번 올리고 5를 꾹 눌렀다 떼서 발사 -> 결과 화면까지 진행
//   - LCD 버스를 엿들어서 화면이 바뀔 때마다 글자로 찍어요 (0~7 은 CGRAM 슬롯 번호로 표시)
//   - FSM 상태가 바뀔 때마다 상태 이름과 체력을 찍어요
// rom/*.mem 파일을 시뮬레이션 소스에 같이 추가하세요. (xsim 실행 시간: 수 분)
// =====================================================================
module tb_fortress_top;
    reg clk = 1'b0;
    always #500 clk = ~clk;                   // 1 MHz

    reg  [11:0] key = 12'd0;
    // DIP: 1 특수포탄 ON, 2 CPU OFF, 3 고수 OFF, 4 이벤트 ON, 5 이동 ON, 6 체력100 OFF, 7 소리 ON, 8 벽 ON
    reg  [7:0]  dip = 8'b1101_1001;
    wire        lcd_e, lcd_rs, lcd_rw, piezo, servo;
    wire [7:0]  lcd_data, seg_data, seg_com, seg1_data, led;
    wire [3:0]  rgb_r, rgb_g, rgb_b, step_coil;

    fortress_top dut (
        .clk(clk), .key(key), .dip(dip), .step_sensor(1'b1),
        .lcd_e(lcd_e), .lcd_rs(lcd_rs), .lcd_rw(lcd_rw), .lcd_data(lcd_data),
        .seg_data(seg_data), .seg_com(seg_com), .seg1_data(seg1_data),
        .led(led), .rgb_r(rgb_r), .rgb_g(rgb_g), .rgb_b(rgb_b),
        .piezo(piezo), .servo(servo), .step_coil(step_coil)
    );

    // ---------------------------------------------------------------- LCD 엿듣기
    reg [7:0] scr [0:31];
    reg [7:0] shown [0:31];
    reg [6:0] ddaddr = 7'd0;
    reg       to_cg = 1'b0;
    integer   i, changed;

    task print_screen;
        begin
            $write("  +----------------+\n  |");
            for (i = 0; i < 16; i = i + 1) $write("%s", (scr[i] < 8) ? (8'h30 + scr[i]) : (scr[i] == 8'hFF ? "#" : (scr[i] == 8'hA5 ? "." : scr[i])));
            $write("|\n  |");
            for (i = 16; i < 32; i = i + 1) $write("%s", (scr[i] < 8) ? (8'h30 + scr[i]) : (scr[i] == 8'hFF ? "#" : (scr[i] == 8'hA5 ? "." : scr[i])));
            $write("|\n  +----------------+  (숫자 = CGRAM 슬롯, # = 꽉 찬 블록)\n");
        end
    endtask

    initial for (i = 0; i < 32; i = i + 1) begin scr[i] = 8'h20; shown[i] = 8'h20; end

    always @(negedge lcd_e) begin
        if (!lcd_rs) begin
            if (lcd_data[7]) begin to_cg = 1'b0; ddaddr = lcd_data[6:0]; end
            else if (lcd_data[7:6] == 2'b01) to_cg = 1'b1;
        end else if (!to_cg) begin
            if (ddaddr < 7'h10)                        scr[ddaddr] = lcd_data;
            else if (ddaddr >= 7'h40 && ddaddr < 7'h50) scr[ddaddr - 7'h40 + 16] = lcd_data;
            ddaddr = ddaddr + 7'd1;
            if (ddaddr == 7'h50) begin                 // 아랫줄 끝 = 한 화면 완성
                changed = 0;
                for (i = 0; i < 32; i = i + 1) if (scr[i] != shown[i]) changed = 1;
                if (changed) begin
                    $display("[%0t ms] LCD", $time / 1000000);
                    print_screen;
                    for (i = 0; i < 32; i = i + 1) shown[i] = scr[i];
                end
            end
        end
    end

    // ---------------------------------------------------------------- 상태 출력
    reg [3:0] last_st = 4'hF;
    always @(posedge clk) begin
        if (dut.u_game.st != last_st) begin
            last_st <= dut.u_game.st;
            $display("[%0t ms] FSM %s  turn=P%0d  HP %0d / %0d  shell=%0d", $time / 1000000,
                st_name(dut.u_game.st), dut.u_game.turn + 1, dut.u_game.p0_disp, dut.u_game.p1_disp, dut.u_game.shot_type);
        end
    end

    function [8*8-1:0] st_name;
        input [3:0] s;
        begin
            case (s)
                4'd0: st_name = "TITLE";   4'd1: st_name = "INTRO";  4'd2: st_name = "AIM";
                4'd3: st_name = "CHARGE";  4'd4: st_name = "FLIGHT"; 4'd5: st_name = "IMPACT";
                4'd6: st_name = "RESULT";  4'd7: st_name = "MOVE";   4'd8: st_name = "METEOR";
                4'd9: st_name = "OVER";    4'd10: st_name = "START"; 4'd11: st_name = "NEXT";
                default: st_name = "SETUP";
            endcase
        end
    endfunction

    // ---------------------------------------------------------------- 키 누르기
    task press;                                // idx: 0='1' 1='2' ... 4='5' ... 11='#'
        input integer idx;
        input integer hold_ms;
        begin
            key[idx] = 1'b1;
            repeat (hold_ms * 1000) @(posedge clk);
            key[idx] = 1'b0;
            repeat (30_000) @(posedge clk);        // 30 ms 쉼
        end
    endtask

    task wait_state;
        input [3:0] s;
        input integer max_ms;
        integer t;
        begin
            t = 0;
            while (dut.u_game.st != s && t < max_ms * 1000) begin @(posedge clk); t = t + 1; end
            if (dut.u_game.st != s) $display("!! 상태 %s 를 %0d ms 안에 못 만남", st_name(s), max_ms);
        end
    endtask

    initial begin
        repeat (200_000) @(posedge clk);        // LCD 초기화 + 타이틀
        $display("== 5 눌러 설정 화면");
        press(4, 50);
        wait_state(4'd12, 100);                 // 설정 화면
        repeat (300_000) @(posedge clk);        // 설정 화면이 LCD에 찍히도록 0.3초
        $display("== 5 눌러 시작");
        press(4, 50);
        wait_state(4'd7, 3000);                 // P1 첫 이동
        press(5, 50);                           // 6: 오른쪽으로 한 칸
        press(4, 50);                           // 5: 이동 끝
        wait_state(4'd7, 3000);                 // P2 첫 이동
        press(4, 50);
        wait_state(4'd2, 3000);                 // P1 조준
        $display("== 각도 올리고 발사");
        press(1, 50); press(1, 50); press(1, 50);
        press(4, 400);                          // 5를 0.4초 누르고 떼기
        wait_state(4'd6, 8000);                 // 결과
        wait_state(4'd7, 5000);                 // 회피 이동
        press(4, 50);
        wait_state(4'd2, 5000);                 // P2 조준
        $display("== P2 얼음 포탄(7) 골라서 발사");
        press(6, 50);
        press(4, 300);
        wait_state(4'd6, 8000);
        repeat (2_000_000) @(posedge clk);
        $display("== 끝");
        $finish;
    end
endmodule
