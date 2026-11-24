// LCD 화면 합성기 (조합회로) - 시뮬레이터 fieldFrame() / titleFrame() / overFrame() + 설정 화면
//   lcd_ctrl 이 주는 주소에 대해
//     dd_addr {줄, 칸} -> 그 칸의 문자 코드 (0~7 = CGRAM 슬롯, 그 외 = 내장 문자)
//     cg_addr {슬롯, 행} -> 그 슬롯 그림의 한 행 (5비트)
//   를 바로 계산해서 돌려줘요. 화면 내용을 따로 저장하지 않아요 (게임 상태가 곧 화면).
//
//   게임 화면 쌓는 순서 (뒤가 위):
//     lcd_field(탱크·벽·용암·!·?·.) -> HUD 글자(빈칸에만) -> 피해 숫자(문구와 안 겹치는 칸) -> 폭발(슬롯7)+'*'
//     -> 포탄 궤적(빈칸에만 가운뎃점) -> 포탄(슬롯7, 화면 위면 '^', 슬롯7을 폭발이 쓰는 중이면 'o')
module lcd_renderer (
    input  wire [3:0]  st,
    input  wire [7:0]  st_t,
    input  wire [7:0]  gt,
    input  wire        cpu_on,
    input  wire [1:0]  winner,
    input  wire [6:0]  title_ang,
    input  wire [7:0]  dip,             // 지금 DIP 상태 (설정 화면 표시용)
    input  wire [2:0]  set_sel,         // 설정 화면에서 설명 중인 DIP 번호

    input  wire [3:0]  p0_pos,
    input  wire [3:0]  p1_pos,
    input  wire [6:0]  p0_ang,
    input  wire [6:0]  p1_ang,
    input  wire        p0_frz,
    input  wire        p1_frz,
    input  wire        p0_inv,
    input  wire        p1_inv,
    input  wire        vis0,
    input  wire        vis1,
    input  wire        q_en,
    input  wire [3:0]  q_col,
    input  wire        m_en,
    input  wire [3:0]  m_col,
    input  wire [7:0]  p0_dmg,
    input  wire [7:0]  p0_heal,
    input  wire [7:0]  p1_dmg,
    input  wire [7:0]  p1_heal,
    input  wire        dmg_show,

    input  wire [5:0]  wall_hp,
    input  wire        wall2_col,
    input  wire [4:0]  lava0,
    input  wire [4:0]  lava1,
    input  wire [14:0] marks,
    input  wire signed [7:0] wind,

    input  wire        sh_draw,
    input  wire        sh_trail_draw,
    input  wire signed [9:0] sh_px,
    input  wire signed [9:0] sh_py,
    input  wire        sh_ice,
    input  wire [31:0] trail,

    input  wire        fx_on,
    input  wire [4:0]  fx_t,
    input  wire [3:0]  fx_col,
    input  wire        fx_row,
    input  wire [1:0]  fx_kind,
    input  wire        fx_big,
    input  wire [15:0] fw_cols,
    input  wire [19:0] fw_ages,

    input  wire [12:0] hud_a,
    input  wire [12:0] hud_b,
    input  wire [12:0] hud_c,
    input  wire [6:0]  cur_ang,
    input  wire [3:0]  cur_pow,

    input  wire [4:0]  dd_addr,
    output reg  [7:0]  dd_char,
    input  wire [5:0]  cg_addr,
    output reg  [4:0]  cg_row
);
    `include "params.vh"
    `include "msg_ids.vh"
    `include "glyph_ids.vh"

    // 0 게임, 1 타이틀, 2 게임 끝, 3 설정
    wire [1:0] mode = (st == ST_TITLE) ? 2'd1 : (st == ST_OVER) ? 2'd2 : (st == ST_SETUP) ? 2'd3 : 2'd0;
    wire       r    = dd_addr[4];
    wire [3:0] c    = dd_addr[3:0];

    // ================================================================ 바닥 레이어 3개
    // A: 지금 쓰는 칸,  B: 폭발 칸 (밑그림 합성용),  C: 포탄 칸 (덮어도 되는지)
    wire [14:0] sp_cm = (sh_px[6:0] * 15'd205);
    wire signed [5:0] scol = sh_px[9] ? -6'sd1 : (sh_px > 10'sd79) ? 6'sd16 : {2'b00, sp_cm[13:10]};
    wire        s_on   = sh_draw && !scol[5] && (scol < 6'sd16);
    wire        s_up   = sh_py[9];                                // 화면 위 (py < 0)
    wire        srow   = (sh_py >= 10'sd8);                       // min(1, py>>3)
    wire [3:0]  sc     = scol[3:0];

    wire       fA_e, fB_e, fC_e;
    wire [7:0] fA, fB, fC;
    wire       blink3 = gt[3];
    lcd_field u_fA (.r(r), .c(c), .vis0(vis0), .vis1(vis1), .p0_pos(p0_pos), .p1_pos(p1_pos),
        .wall_hp(wall_hp), .wall2_col(wall2_col), .lava0(lava0), .lava1(lava1), .marks(marks), .mark_blink(blink3),
        .q_en(q_en), .q_col(q_col), .m_en(m_en), .m_col(m_col), .empty(fA_e), .code(fA));
    lcd_field u_fB (.r(fx_row), .c(fx_col), .vis0(vis0), .vis1(vis1), .p0_pos(p0_pos), .p1_pos(p1_pos),
        .wall_hp(wall_hp), .wall2_col(wall2_col), .lava0(lava0), .lava1(lava1), .marks(marks), .mark_blink(blink3),
        .q_en(q_en), .q_col(q_col), .m_en(m_en), .m_col(m_col), .empty(fB_e), .code(fB));
    lcd_field u_fC (.r(srow), .c(sc), .vis0(vis0), .vis1(vis1), .p0_pos(p0_pos), .p1_pos(p1_pos),
        .wall_hp(wall_hp), .wall2_col(wall2_col), .lava0(lava0), .lava1(lava1), .marks(marks), .mark_blink(blink3),
        .q_en(q_en), .q_col(q_col), .m_en(m_en), .m_col(m_col), .empty(fC_e), .code(fC));

    // 포탄이 슬롯7 스프라이트로 그려지는가 (폭발이 슬롯7을 안 쓰고, 그 칸이 탱크·벽 칸이 아닐 때)
    wire shell_sprite = s_on && !s_up && !fx_on && !(!fC_e && (fC < 8'd8 || fC == CH_FULL));

    // ================================================================ 글자 묶음 (span)
    // 게임: 윗줄에 HUD 3개.  타이틀·게임 끝: 줄마다 정해진 문구
    reg  [12:0] spA, spB, spC;
    wire        title_ph = gt[4];                         // (t>>4)%2
    wire [5:0]  win_msg  = (winner == 2'd0) ? MSG_P1_WINS_X : cpu_on ? MSG_CPU_WINS_X : MSG_P2_WINS_X;
    always @(*) begin
        spA = 13'd0; spB = 13'd0; spC = 13'd0;
        case (mode)
            2'd1: if (!r) spA = {1'b1, MSG_FORTRESS, 2'd0, 4'd4};
                  else if (!title_ph) spA = {1'b1, MSG_PUSH_5_TO_START, 2'd0, 4'd0};
                  else spA = {1'b1, MSG_SHELLS, 2'd0, 4'd1};
            2'd2: if (!r) spA = (winner == 2'd2) ? {1'b1, MSG_DRAW_GAME_X, 2'd0, 4'd3} : {1'b1, win_msg, 2'd3, 4'd0};
                  else    spA = {(st_t > 8'd40) && title_ph, MSG_PUSH_5_AGAIN, 2'd0, 4'd0};
            // 설정:  윗줄 "SETUP   12-4-678" ("SETUP" <-> "5:START" 번갈아), 아랫줄 "3 CPU HARD    ON"
            2'd3: if (!r) spA = {1'b1, gt[5] ? MSG_5_START : MSG_SETUP, 2'd0, 4'd0};
                  else begin
                      spA = {1'b1, MSG_1_SPECIAL_SH + {3'd0, set_sel}, 2'd0, 4'd0};
                      spB = {1'b1, dip[set_sel] ? MSG_ON : MSG_OFF, 2'd1, 4'd0};
                  end
            default: if (!r) begin spA = hud_a; spB = hud_b; spC = hud_c; end
        endcase
    end

    wire hA, hB, hC;
    wire [7:0] chA, chB, chC;
    wire hud_hit  = hA || hB || hC;
    wire num_wins = (st == ST_METEOR);
    hud_span u_sA (.span(spA), .c(c), .aim_ang(cur_ang), .aim_pow(cur_pow), .wind(wind), .hit(hA), .ch(chA));
    hud_span u_sB (.span(spB), .c(c), .aim_ang(cur_ang), .aim_pow(cur_pow), .wind(wind), .hit(hB), .ch(chB));
    hud_span u_sC (.span(spC), .c(c), .aim_ang(cur_ang), .aim_pow(cur_pow), .wind(wind), .hit(hC), .ch(chC));

    // ================================================================ 피해 숫자 "-35" / "+15"
    function [7:0] num_char;            // 값 v를 sign 붙여 쓴 문자열의 k번째 글자, 없으면 0
        input [7:0] v;
        input       plus;
        input [3:0] k;
        reg [3:0] h, t, o;
        begin
            h = v / 100; t = (v / 10) % 10; o = v % 10;
            if (k == 4'd0) num_char = plus ? CH_PLUS : CH_MINUS;
            else if (h != 0)
                num_char = (k == 4'd1) ? 8'h30 + h : (k == 4'd2) ? 8'h30 + t : (k == 4'd3) ? 8'h30 + o : 8'd0;
            else if (t != 0)
                num_char = (k == 4'd1) ? 8'h30 + t : (k == 4'd2) ? 8'h30 + o : 8'd0;
            else
                num_char = (k == 4'd1) ? 8'h30 + o : 8'd0;
        end
    endfunction

    wire [7:0] v0 = (p0_dmg != 0) ? p0_dmg : p0_heal;
    wire [7:0] v1 = (p1_dmg != 0) ? p1_dmg : p1_heal;
    wire [3:0] d0s = p0_pos, d1s = p1_pos - 4'd2;
    wire [7:0] dn0 = (dmg_show && v0 != 0 && c >= d0s) ? num_char(v0, p0_dmg == 0, c - d0s) : 8'd0;
    wire [7:0] dn1 = (dmg_show && v1 != 0 && c >= d1s) ? num_char(v1, p1_dmg == 0, c - d1s) : 8'd0;

    // ================================================================ 불꽃놀이 (게임 끝 아랫줄)
    reg [7:0] fw_ch;
    reg       fw_hit;
    reg [4:0] fa;
    reg [3:0] fc;
    integer   i;
    always @(*) begin
        fw_hit = 1'b0; fw_ch = CH_SPACE;
        for (i = 0; i < 4; i = i + 1) begin
            fa = fw_ages[i*5 +: 5];
            fc = fw_cols[i*4 +: 4];
            if (fa < 5'd24) begin
                if (c == fc) begin
                    fw_hit = 1'b1;
                    case (fa[4:2])
                        3'd0: fw_ch = CH_MARK;
                        3'd1: fw_ch = CH_DOT;
                        3'd2: fw_ch = CH_PLUS;
                        3'd3: fw_ch = CH_STAR;
                        3'd4: fw_ch = CH_PLUS;
                        default: fw_ch = CH_DOT;
                    endcase
                end else if (fa >= 5'd8 && fa < 5'd16 && ({1'b0, c} == fc + 5'd1 || c + 5'd1 == {1'b0, fc}) && !fw_hit) begin
                    fw_hit = 1'b1; fw_ch = CH_DOT;
                end
            end
        end
    end

    // ================================================================ 설정 화면 DIP 줄 (윗줄 8~15칸)
    //   켜진 스위치는 번호, 꺼진 스위치는 '-'. 지금 설명 중인 스위치는 깜빡임
    wire [2:0] dip_i  = c[2:0];
    wire [7:0] dip_ch = (dip_i == set_sel && gt[3]) ? CH_SPACE : dip[dip_i] ? 8'h31 + {5'd0, dip_i} : CH_MINUS;

    // ================================================================ DDRAM 문자 합성
    reg [7:0] v;
    reg       e;
    always @(*) begin
        v = CH_SPACE; e = 1'b1;
        case (mode)
            2'd1: begin // ---- 타이틀
                if (hA) begin v = chA; e = 1'b0; end
                if (!r) begin
                    if (c == 4'd0)  v = {5'd0, SLOT_P1};
                    if (c == 4'd1)  v = {5'd0, SLOT_P1C};
                    if (c == 4'd14) v = {5'd0, SLOT_P2C};
                    if (c == 4'd15) v = {5'd0, SLOT_P2};
                end else if (title_ph) begin
                    if (c == 4'd8)  v = 8'd4;
                    if (c == 4'd10) v = 8'd5;
                    if (c == 4'd12) v = 8'd6;
                    if (c == 4'd14) v = 8'd7;
                end
            end
            2'd2: begin // ---- 게임 끝
                if (hA) begin v = chA; e = 1'b0; end
                if (!r && winner != 2'd2) begin
                    if (c == 4'd1)  v = winner[0] ? {5'd0, SLOT_P2} : {5'd0, SLOT_P1};
                    if (c == 4'd14) v = 8'd4;                       // 트로피
                end
                if (r && e && fw_hit) v = fw_ch;
            end
            2'd3: begin // ---- 설정
                if (hA) v = chA;
                if (hB) v = chB;
                if (!r && c[3]) v = dip_ch;
            end
            default: begin // ---- 게임 화면
                v = fA; e = fA_e;
                if (e && hud_hit) begin
                    v = hA ? chA : hB ? chB : chC; e = 1'b0;
                end
                // 피해 숫자: 결과 문구와 겹치는 칸은 문구가 이김 (유성 때는 숫자가 이김)
                if (!r && dn0 != 8'd0 && (num_wins || !hud_hit)) begin v = dn0; e = 1'b0; end
                if (!r && dn1 != 8'd0 && (num_wins || !hud_hit)) begin v = dn1; e = 1'b0; end
                // 폭발
                if (fx_on && r == fx_row && c == fx_col) begin
                    v = {5'd0, SLOT_SPR}; e = 1'b0;
                end else if (fx_on && fx_big && fx_t >= 5'd4 && fx_t < 5'd16 && r == fx_row &&
                             ({1'b0, c} == fx_col + 5'd1 || c + 5'd1 == {1'b0, fx_col}) && e) begin
                    v = CH_STAR; e = 1'b0;
                end
                // 포탄 궤적
                if (sh_trail_draw && trail[{r, c}] && e) begin v = CH_DOT; e = 1'b0; end
                // 포탄
                if (s_on && c == sc) begin
                    if (s_up) begin
                        if (!r && (e || v == CH_DOT)) begin v = CH_UP; e = 1'b0; end
                    end else if (r == srow && !(!e && (v < 8'd8 || v == CH_FULL))) begin
                        v = fx_on ? CH_SMALLO : {5'd0, SLOT_SPR}; e = 1'b0;
                    end
                end
            end
        endcase
        dd_char = v;
    end

    // ================================================================ CGRAM 행 합성
    wire [2:0] cslot = cg_addr[5:3];
    wire [2:0] crow  = cg_addr[2:0];

    // 슬롯 0~6 (그리고 타이틀 7)
    wire [4:0] slot_bits;
    cgram_slot u_slotA (.mode(mode), .slot(cslot), .row(crow), .p0_ang(p0_ang), .p1_ang(p1_ang),
        .title_ang(title_ang), .p0_frz(p0_frz), .p1_frz(p1_frz), .p0_inv(p0_inv), .p1_inv(p1_inv), .bits(slot_bits));

    // 폭발 칸 밑그림 (그 칸이 슬롯 그림이면 겹쳐 그림)
    wire       base_slot = !fB_e && (fB < 8'd7);
    wire [4:0] base_bits;
    cgram_slot u_slotB (.mode(2'd0), .slot(fB[2:0]), .row(crow), .p0_ang(p0_ang), .p1_ang(p1_ang),
        .title_ang(title_ang), .p0_frz(p0_frz), .p1_frz(p1_frz), .p0_inv(p0_inv), .p1_inv(p1_inv), .bits(base_bits));

    // 폭발 프레임 (6프레임, 4틱씩)
    wire [2:0] fr    = (fx_t[4:2] > 3'd5) ? 3'd5 : fx_t[4:2];
    wire [4:0] ex_gid = (fx_kind == 2'd1) ? GLY_EXP_I0 + fr : (fx_kind == 2'd2) ? GLY_EXP_F0 + fr : GLY_EXP_N0 + fr;
    wire [4:0] ex_bits;
    glyph_rom u_exp (.gid(ex_gid), .row(crow), .bits(ex_bits));

    // 포탄 스프라이트 (칸 안 위치에 2x2 점, 얼음은 + 모양)
    wire [9:0] lx_w = sh_px - sc * 5;
    wire [9:0] ly_w = sh_py - {srow, 3'd0};
    wire [2:0] lx   = lx_w[2:0];
    wire [2:0] ly   = (ly_w > 10'd7) ? 3'd7 : ly_w[2:0];
    wire [2:0] nx   = sh_ice ? ((lx < 3'd1) ? 3'd1 : (lx > 3'd3) ? 3'd3 : lx) : ((lx > 3'd3) ? 3'd3 : lx);
    wire [2:0] ny   = sh_ice ? ((ly < 3'd1) ? 3'd1 : (ly > 3'd6) ? 3'd6 : ly) : ((ly > 3'd6) ? 3'd6 : ly);
    wire [4:0] px1  = 5'b10000 >> nx;           // x 위치 비트 (bit4 = 왼쪽)
    reg  [4:0] spr_bits;
    always @(*) begin
        spr_bits = 5'd0;
        if (sh_ice) begin
            if (crow == ny)                          spr_bits = px1 | (px1 << 1) | (px1 >> 1);
            else if (crow + 3'd1 == ny || crow == ny + 3'd1) spr_bits = px1;
        end else begin
            if (crow == ny || crow == ny + 3'd1)     spr_bits = px1 | (px1 >> 1);
        end
    end

    always @(*) begin
        if (mode == 2'd0 && cslot == SLOT_SPR) begin
            if (fx_on)             cg_row = ex_bits | (base_slot ? base_bits : 5'd0);
            else if (shell_sprite) cg_row = spr_bits;
            else                   cg_row = 5'd0;
        end else begin
            cg_row = slot_bits;
        end
    end
endmodule
