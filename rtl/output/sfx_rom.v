// 효과음 ROM (자동 생성: tools/gen_roms.py) - 손으로 고치지 말고 gen_roms.py의 SFX 표를 고치세요
// 항목 = {last[29], noise[28], mask_bits[27:24], dur_ms[23:14], half_us[13:0]}
//   half_us: 1MHz 기준 반주기(0이면 쉼).  noise면 half_us + (난수 & (2^mask_bits-1))
module sfx_rom (
    input  wire [4:0]  sfx_id,
    output reg  [6:0]  start_addr,
    input  wire [6:0]  addr,
    output reg  [29:0] entry
);
    always @(*) begin
        case (sfx_id)
            5'd0: start_addr = 7'd0;  // NONE
            5'd1: start_addr = 7'd1;  // TICK
            5'd2: start_addr = 7'd2;  // ERR
            5'd3: start_addr = 7'd3;  // MOVE
            5'd4: start_addr = 7'd6;  // FIRE
            5'd5: start_addr = 7'd14;  // BOOM
            5'd6: start_addr = 7'd15;  // BOOM_BIG
            5'd7: start_addr = 7'd16;  // HIT
            5'd8: start_addr = 7'd23;  // MISS
            5'd9: start_addr = 7'd28;  // ARM
            5'd10: start_addr = 7'd32;  // TURN
            5'd11: start_addr = 7'd36;  // START
            5'd12: start_addr = 7'd46;  // WIN
            5'd13: start_addr = 7'd61;  // LOSE
            5'd14: start_addr = 7'd72;  // OUT
            5'd15: start_addr = 7'd78;  // FREEZE
            5'd16: start_addr = 7'd86;  // BURN
            5'd17: start_addr = 7'd87;  // HEAL
            5'd18: start_addr = 7'd94;  // ROUL
            5'd19: start_addr = 7'd95;  // FANFARE
            5'd20: start_addr = 7'd105;  // METEOR
            5'd21: start_addr = 7'd117;  // SPARK
            5'd22: start_addr = 7'd118;  // QUAKE
            default: start_addr = 7'd0;
        endcase
    end

    always @(*) begin
        case (addr)
            7'd0: entry = {1'b1, 1'b0, 4'd0, 10'd1, 14'd0};  // NONE rest
            7'd1: entry = {1'b1, 1'b0, 4'd0, 10'd12, 14'd278};  // TICK 1800Hz
            7'd2: entry = {1'b1, 1'b0, 4'd0, 10'd140, 14'd3571};  // ERR 140Hz
            7'd3: entry = {1'b0, 1'b0, 4'd0, 10'd40, 14'd1515};  // MOVE 330Hz
            7'd4: entry = {1'b0, 1'b0, 4'd0, 10'd10, 14'd0};  // MOVE rest
            7'd5: entry = {1'b1, 1'b0, 4'd0, 10'd40, 14'd1908};  // MOVE 262Hz
            7'd6: entry = {1'b0, 1'b0, 4'd0, 10'd25, 14'd385};  // FIRE 1300Hz
            7'd7: entry = {1'b0, 1'b0, 4'd0, 10'd25, 14'd514};  // FIRE 972Hz
            7'd8: entry = {1'b0, 1'b0, 4'd0, 10'd25, 14'd688};  // FIRE 727Hz
            7'd9: entry = {1'b0, 1'b0, 4'd0, 10'd25, 14'd919};  // FIRE 544Hz
            7'd10: entry = {1'b0, 1'b0, 4'd0, 10'd25, 14'd1229};  // FIRE 407Hz
            7'd11: entry = {1'b0, 1'b0, 4'd0, 10'd25, 14'd1645};  // FIRE 304Hz
            7'd12: entry = {1'b0, 1'b0, 4'd0, 10'd25, 14'd2203};  // FIRE 227Hz
            7'd13: entry = {1'b1, 1'b0, 4'd0, 10'd25, 14'd2941};  // FIRE 170Hz
            7'd14: entry = {1'b1, 1'b1, 4'd13, 10'd380, 14'd1667};  // BOOM noise 50-300Hz
            7'd15: entry = {1'b1, 1'b1, 4'd12, 10'd700, 14'd2273};  // BOOM_BIG noise 50-220Hz
            7'd16: entry = {1'b0, 1'b0, 4'd0, 10'd250, 14'd0};  // HIT rest
            7'd17: entry = {1'b0, 1'b0, 4'd0, 10'd60, 14'd568};  // HIT 880Hz
            7'd18: entry = {1'b0, 1'b0, 4'd0, 10'd10, 14'd0};  // HIT rest
            7'd19: entry = {1'b0, 1'b0, 4'd0, 10'd60, 14'd426};  // HIT 1175Hz
            7'd20: entry = {1'b0, 1'b0, 4'd0, 10'd10, 14'd0};  // HIT rest
            7'd21: entry = {1'b0, 1'b0, 4'd0, 10'd60, 14'd319};  // HIT 1568Hz
            7'd22: entry = {1'b1, 1'b0, 4'd0, 10'd10, 14'd0};  // HIT rest
            7'd23: entry = {1'b0, 1'b0, 4'd0, 10'd200, 14'd0};  // MISS rest
            7'd24: entry = {1'b0, 1'b0, 4'd0, 10'd85, 14'd1276};  // MISS 392Hz
            7'd25: entry = {1'b0, 1'b0, 4'd0, 10'd15, 14'd0};  // MISS rest
            7'd26: entry = {1'b0, 1'b0, 4'd0, 10'd85, 14'd1515};  // MISS 330Hz
            7'd27: entry = {1'b1, 1'b0, 4'd0, 10'd15, 14'd0};  // MISS rest
            7'd28: entry = {1'b0, 1'b0, 4'd0, 10'd51, 14'd758};  // ARM 660Hz
            7'd29: entry = {1'b0, 1'b0, 4'd0, 10'd9, 14'd0};  // ARM rest
            7'd30: entry = {1'b0, 1'b0, 4'd0, 10'd51, 14'd505};  // ARM 990Hz
            7'd31: entry = {1'b1, 1'b0, 4'd0, 10'd9, 14'd0};  // ARM rest
            7'd32: entry = {1'b0, 1'b0, 4'd0, 10'd68, 14'd956};  // TURN 523Hz
            7'd33: entry = {1'b0, 1'b0, 4'd0, 10'd12, 14'd0};  // TURN rest
            7'd34: entry = {1'b0, 1'b0, 4'd0, 10'd68, 14'd638};  // TURN 784Hz
            7'd35: entry = {1'b1, 1'b0, 4'd0, 10'd12, 14'd0};  // TURN rest
            7'd36: entry = {1'b0, 1'b0, 4'd0, 10'd76, 14'd1276};  // START 392Hz
            7'd37: entry = {1'b0, 1'b0, 4'd0, 10'd14, 14'd0};  // START rest
            7'd38: entry = {1'b0, 1'b0, 4'd0, 10'd76, 14'd956};  // START 523Hz
            7'd39: entry = {1'b0, 1'b0, 4'd0, 10'd14, 14'd0};  // START rest
            7'd40: entry = {1'b0, 1'b0, 4'd0, 10'd76, 14'd759};  // START 659Hz
            7'd41: entry = {1'b0, 1'b0, 4'd0, 10'd14, 14'd0};  // START rest
            7'd42: entry = {1'b0, 1'b0, 4'd0, 10'd76, 14'd638};  // START 784Hz
            7'd43: entry = {1'b0, 1'b0, 4'd0, 10'd14, 14'd0};  // START rest
            7'd44: entry = {1'b0, 1'b0, 4'd0, 10'd76, 14'd478};  // START 1047Hz
            7'd45: entry = {1'b1, 1'b0, 4'd0, 10'd14, 14'd0};  // START rest
            7'd46: entry = {1'b0, 1'b0, 4'd0, 10'd110, 14'd956};  // WIN 523Hz
            7'd47: entry = {1'b0, 1'b0, 4'd0, 10'd20, 14'd0};  // WIN rest
            7'd48: entry = {1'b0, 1'b0, 4'd0, 10'd110, 14'd759};  // WIN 659Hz
            7'd49: entry = {1'b0, 1'b0, 4'd0, 10'd20, 14'd0};  // WIN rest
            7'd50: entry = {1'b0, 1'b0, 4'd0, 10'd110, 14'd638};  // WIN 784Hz
            7'd51: entry = {1'b0, 1'b0, 4'd0, 10'd20, 14'd0};  // WIN rest
            7'd52: entry = {1'b0, 1'b0, 4'd0, 10'd110, 14'd478};  // WIN 1047Hz
            7'd53: entry = {1'b0, 1'b0, 4'd0, 10'd20, 14'd0};  // WIN rest
            7'd54: entry = {1'b0, 1'b0, 4'd0, 10'd130, 14'd0};  // WIN rest
            7'd55: entry = {1'b0, 1'b0, 4'd0, 10'd110, 14'd638};  // WIN 784Hz
            7'd56: entry = {1'b0, 1'b0, 4'd0, 10'd20, 14'd0};  // WIN rest
            7'd57: entry = {1'b0, 1'b0, 4'd0, 10'd110, 14'd478};  // WIN 1047Hz
            7'd58: entry = {1'b0, 1'b0, 4'd0, 10'd20, 14'd0};  // WIN rest
            7'd59: entry = {1'b0, 1'b0, 4'd0, 10'd110, 14'd478};  // WIN 1047Hz
            7'd60: entry = {1'b1, 1'b0, 4'd0, 10'd20, 14'd0};  // WIN rest
            7'd61: entry = {1'b0, 1'b0, 4'd0, 10'd153, 14'd1276};  // LOSE 392Hz
            7'd62: entry = {1'b0, 1'b0, 4'd0, 10'd27, 14'd0};  // LOSE rest
            7'd63: entry = {1'b0, 1'b0, 4'd0, 10'd153, 14'd1351};  // LOSE 370Hz
            7'd64: entry = {1'b0, 1'b0, 4'd0, 10'd27, 14'd0};  // LOSE rest
            7'd65: entry = {1'b0, 1'b0, 4'd0, 10'd153, 14'd1433};  // LOSE 349Hz
            7'd66: entry = {1'b0, 1'b0, 4'd0, 10'd27, 14'd0};  // LOSE rest
            7'd67: entry = {1'b0, 1'b0, 4'd0, 10'd153, 14'd1515};  // LOSE 330Hz
            7'd68: entry = {1'b0, 1'b0, 4'd0, 10'd27, 14'd0};  // LOSE rest
            7'd69: entry = {1'b0, 1'b0, 4'd0, 10'd180, 14'd0};  // LOSE rest
            7'd70: entry = {1'b0, 1'b0, 4'd0, 10'd153, 14'd1908};  // LOSE 262Hz
            7'd71: entry = {1'b1, 1'b0, 4'd0, 10'd27, 14'd0};  // LOSE rest
            7'd72: entry = {1'b0, 1'b0, 4'd0, 10'd42, 14'd714};  // OUT 700Hz
            7'd73: entry = {1'b0, 1'b0, 4'd0, 10'd42, 14'd877};  // OUT 570Hz
            7'd74: entry = {1'b0, 1'b0, 4'd0, 10'd42, 14'd1078};  // OUT 464Hz
            7'd75: entry = {1'b0, 1'b0, 4'd0, 10'd42, 14'd1326};  // OUT 377Hz
            7'd76: entry = {1'b0, 1'b0, 4'd0, 10'd42, 14'd1629};  // OUT 307Hz
            7'd77: entry = {1'b1, 1'b0, 4'd0, 10'd42, 14'd2000};  // OUT 250Hz
            7'd78: entry = {1'b0, 1'b0, 4'd0, 10'd42, 14'd239};  // FREEZE 2093Hz
            7'd79: entry = {1'b0, 1'b0, 4'd0, 10'd8, 14'd0};  // FREEZE rest
            7'd80: entry = {1'b0, 1'b0, 4'd0, 10'd42, 14'd319};  // FREEZE 1568Hz
            7'd81: entry = {1'b0, 1'b0, 4'd0, 10'd8, 14'd0};  // FREEZE rest
            7'd82: entry = {1'b0, 1'b0, 4'd0, 10'd42, 14'd190};  // FREEZE 2637Hz
            7'd83: entry = {1'b0, 1'b0, 4'd0, 10'd8, 14'd0};  // FREEZE rest
            7'd84: entry = {1'b0, 1'b0, 4'd0, 10'd42, 14'd239};  // FREEZE 2093Hz
            7'd85: entry = {1'b1, 1'b0, 4'd0, 10'd8, 14'd0};  // FREEZE rest
            7'd86: entry = {1'b1, 1'b1, 4'd9, 10'd350, 14'd417};  // BURN noise 400-1200Hz
            7'd87: entry = {1'b0, 1'b1, 4'd13, 10'd300, 14'd1667};  // HEAL noise 50-300Hz
            7'd88: entry = {1'b0, 1'b0, 4'd0, 10'd60, 14'd759};  // HEAL 659Hz
            7'd89: entry = {1'b0, 1'b0, 4'd0, 10'd10, 14'd0};  // HEAL rest
            7'd90: entry = {1'b0, 1'b0, 4'd0, 10'd60, 14'd638};  // HEAL 784Hz
            7'd91: entry = {1'b0, 1'b0, 4'd0, 10'd10, 14'd0};  // HEAL rest
            7'd92: entry = {1'b0, 1'b0, 4'd0, 10'd60, 14'd478};  // HEAL 1047Hz
            7'd93: entry = {1'b1, 1'b0, 4'd0, 10'd10, 14'd0};  // HEAL rest
            7'd94: entry = {1'b1, 1'b0, 4'd0, 10'd12, 14'd333};  // ROUL 1500Hz
            7'd95: entry = {1'b0, 1'b0, 4'd0, 10'd60, 14'd956};  // FANFARE 523Hz
            7'd96: entry = {1'b0, 1'b0, 4'd0, 10'd10, 14'd0};  // FANFARE rest
            7'd97: entry = {1'b0, 1'b0, 4'd0, 10'd60, 14'd759};  // FANFARE 659Hz
            7'd98: entry = {1'b0, 1'b0, 4'd0, 10'd10, 14'd0};  // FANFARE rest
            7'd99: entry = {1'b0, 1'b0, 4'd0, 10'd60, 14'd638};  // FANFARE 784Hz
            7'd100: entry = {1'b0, 1'b0, 4'd0, 10'd10, 14'd0};  // FANFARE rest
            7'd101: entry = {1'b0, 1'b0, 4'd0, 10'd60, 14'd478};  // FANFARE 1047Hz
            7'd102: entry = {1'b0, 1'b0, 4'd0, 10'd10, 14'd0};  // FANFARE rest
            7'd103: entry = {1'b0, 1'b0, 4'd0, 10'd60, 14'd379};  // FANFARE 1319Hz
            7'd104: entry = {1'b1, 1'b0, 4'd0, 10'd10, 14'd0};  // FANFARE rest
            7'd105: entry = {1'b0, 1'b0, 4'd0, 10'd75, 14'd208};  // METEOR 2400Hz
            7'd106: entry = {1'b0, 1'b0, 4'd0, 10'd75, 14'd252};  // METEOR 1987Hz
            7'd107: entry = {1'b0, 1'b0, 4'd0, 10'd75, 14'd304};  // METEOR 1644Hz
            7'd108: entry = {1'b0, 1'b0, 4'd0, 10'd75, 14'd367};  // METEOR 1361Hz
            7'd109: entry = {1'b0, 1'b0, 4'd0, 10'd75, 14'd444};  // METEOR 1127Hz
            7'd110: entry = {1'b0, 1'b0, 4'd0, 10'd75, 14'd536};  // METEOR 933Hz
            7'd111: entry = {1'b0, 1'b0, 4'd0, 10'd75, 14'd648};  // METEOR 772Hz
            7'd112: entry = {1'b0, 1'b0, 4'd0, 10'd75, 14'd782};  // METEOR 639Hz
            7'd113: entry = {1'b0, 1'b0, 4'd0, 10'd75, 14'd945};  // METEOR 529Hz
            7'd114: entry = {1'b0, 1'b0, 4'd0, 10'd75, 14'd1142};  // METEOR 438Hz
            7'd115: entry = {1'b0, 1'b0, 4'd0, 10'd75, 14'd1381};  // METEOR 362Hz
            7'd116: entry = {1'b1, 1'b0, 4'd0, 10'd75, 14'd1667};  // METEOR 300Hz
            7'd117: entry = {1'b1, 1'b0, 4'd0, 10'd30, 14'd333};  // SPARK 1500Hz
            7'd118: entry = {1'b1, 1'b1, 4'd13, 10'd900, 14'd4167};  // QUAKE noise 40-120Hz
            default: entry = {1'b1, 1'b0, 4'd0, 10'd1, 14'd0};
        endcase
    end
endmodule
