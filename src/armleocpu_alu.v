module armleocpu_alu(
    input               is_op,
    input               is_op_imm,

    input      [4:0]    shamt,
    input      [6:0]    funct7,
    input      [2:0]    funct3,
    
    input      [31:0]   rs1,
    input      [31:0]   rs2,
    input      [31:0]   simm12,


    
    output reg [31:0]   result,
    output reg          illegal_instruction
);


wire is_addi        = is_op_imm && (funct3 == 3'b000);
wire is_slti        = is_op_imm && (funct3 == 3'b010);
wire is_sltiu       = is_op_imm && (funct3 == 3'b011);
wire is_xori        = is_op_imm && (funct3 == 3'b100);
wire is_ori         = is_op_imm && (funct3 == 3'b110);
wire is_andi        = is_op_imm && (funct3 == 3'b111);

wire is_slli        = is_op_imm && (funct3 == 3'b001) && (funct7 == 7'b0000_000);
wire is_srli        = is_op_imm && (funct3 == 3'b101) && (funct7 == 7'b0000_000);
wire is_srai        = is_op_imm && (funct3 == 3'b101) && (funct7 == 7'b0100_000);

wire is_add         = is_op     && (funct3 == 3'b000) && (funct7 == 7'b0000_000);
wire is_sub         = is_op     && (funct3 == 3'b000) && (funct7 == 7'b0100_000);
wire is_slt         = is_op     && (funct3 == 3'b010) && (funct7 == 7'b0000_000);
wire is_sltu        = is_op     && (funct3 == 3'b011) && (funct7 == 7'b0000_000);
wire is_xor         = is_op     && (funct3 == 3'b100) && (funct7 == 7'b0000_000);
wire is_or          = is_op     && (funct3 == 3'b110) && (funct7 == 7'b0000_000);
wire is_and         = is_op     && (funct3 == 3'b111) && (funct7 == 7'b0000_000);

wire is_sll         = is_op     && (funct3 == 3'b001) && (funct7 == 7'b0000_000);
wire is_srl         = is_op     && (funct3 == 3'b101) && (funct7 == 7'b0000_000);
wire is_sra         = is_op     && (funct3 == 3'b101) && (funct7 == 7'b0100_000);


wire [31:0] internal_op2     = is_op ? rs2 : simm12;
/* verilator lint_off WIDTH */
wire [4:0] internal_shamt   = is_op_imm ? shamt : rs2[4:0];
/* verilator lint_on WIDTH */

always @* begin
    illegal_instruction = 0;

    case(1)
        is_addi, is_add:        result = rs1 + internal_op2;
        is_sub:                 result = rs1 - rs2;
        /* verilator lint_off WIDTH */
        is_slt, is_slti:        result = ($signed(rs1) < $signed(internal_op2));
        is_sltu, is_sltiu:      result = ($unsigned(rs1) < $unsigned(internal_op2));
        /* verilator lint_on WIDTH */
        is_sll, is_slli:        result = rs1 << internal_shamt;
        /* verilator lint_off WIDTH */
        is_sra, is_srai:        result = {{32{rs1[31]}}, rs1} >> internal_shamt;
        /* verilator lint_on WIDTH */
        is_srl, is_srli:        result = rs1 >> internal_shamt;

        is_xor, is_xori:        result = rs1 ^ internal_op2;
        is_or, is_ori:          result = rs1 | internal_op2;
        is_and, is_andi:        result = rs1 & internal_op2;
        default: begin
            illegal_instruction = 1;
            result = rs1 + internal_op2;
        end
    endcase
end

endmodule
