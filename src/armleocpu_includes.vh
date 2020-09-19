// ALU_OUTPUT_SELECT
`define ALU_SELECT_ADD 4'd0
`define ALU_SELECT_SUB 4'd1
`define ALU_SELECT_SLT 4'd2
`define ALU_SELECT_SLTU 4'd3
`define ALU_SELECT_SLL 4'd4
`define ALU_SELECT_SRA 4'd5
`define ALU_SELECT_SRL 4'd6
`define ALU_SELECT_XOR 4'd7
`define ALU_SELECT_OR 4'd8
`define ALU_SELECT_AND 4'd9

`define ALU_SELECT_WIDTH 4

// LD_TYPE
`define LOAD_BYTE (3'b000)
`define LOAD_BYTE_UNSIGNED (3'b100)
`define LOAD_HALF (3'b001)
`define LOAD_HALF_UNSIGNED (3'b101)
`define LOAD_WORD (3'b010)

// ST_TYPE
`define STORE_BYTE (2'b00)
`define STORE_HALF (2'b01)
`define STORE_WORD (2'b10)

// CSR CMD
`define ARMLEOCPU_CSR_CMD_NONE (4'd0)
`define ARMLEOCPU_CSR_CMD_READ (4'd1)
`define ARMLEOCPU_CSR_CMD_WRITE (4'd2)
`define ARMLEOCPU_CSR_CMD_READ_WRITE (4'd3)
`define ARMLEOCPU_CSR_CMD_READ_SET (4'd4)
`define ARMLEOCPU_CSR_CMD_READ_CLEAR (4'd5)
`define ARMLEOCPU_CSR_CMD_MRET (4'd6)
`define ARMLEOCPU_CSR_CMD_SRET (4'd7)
`define ARMLEOCPU_CSR_CMD_INTERRUPT_BEGIN (4'd8)


// Exceptions and interrupts
`define EXCEPTION_CODE_INTERRUPT (32'h8000_0000)
`define INTERRUPT_CODE_SOFTWATE_INTERRUPT (3)
`define INTERRUPT_CODE_TIMER_INTERRUPT (7)
`define INTERRUPT_CODE_EXTERNAL_INTERRUPT (11)

`define EXCEPTION_CODE_SOFTWATE_INTERRUPT (`INTERRUPT_CODE_SOFTWATE_INTERRUPT | `EXCEPTION_CODE_INTERRUPT)
`define EXCEPTION_CODE_TIMER_INTERRUPT (`INTERRUPT_CODE_TIMER_INTERRUPT | `EXCEPTION_CODE_INTERRUPT)
`define EXCEPTION_CODE_EXTERNAL_INTERRUPT (`INTERRUPT_CODE_EXTERNAL_INTERRUPT | `EXCEPTION_CODE_INTERRUPT)

`define EXCEPTION_CODE_INSTRUCTION_ADDRESS_MISSALIGNED (0)
`define EXCEPTION_CODE_INSTRUCTION_ACCESS_FAULT (1)
`define EXCEPTION_CODE_ILLEGAL_INSTRUCTION (2)
`define EXCEPTION_CODE_BREAKPOINT (3)
`define EXCEPTION_CODE_LOAD_ADDRESS_MISSALIGNED (4)
`define EXCEPTION_CODE_LOAD_ACCESS_FAULT (5)
`define EXCEPTION_CODE_STORE_ADDRESS_MISSALIGNED (6)
`define EXCEPTION_CODE_STORE_ACCESS_FAULT (7)

// Calls from x privilege
`define EXCEPTION_CODE_UCALL (8)
`define EXCEPTION_CODE_SCALL (9)
`define EXCEPTION_CODE_MCALL (11)
`define EXCEPTION_CODE_INSTRUCTION_PAGE_FAULT (12)
`define EXCEPTION_CODE_LOAD_PAGE_FAULT (13)
`define EXCEPTION_CODE_STORE_PAGE_FAULT (15)

// Privilege modes
// Sv means supervisor, because spp can only hold one bit
`define ARMLEOCPU_PRIVILEGE_USER (2'b00)
`define ARMLEOCPU_PRIVILEGE_USER_SV (1'b0)
`define ARMLEOCPU_PRIVILEGE_SUPERVISOR (2'b01)
`define ARMLEOCPU_PRIVILEGE_SUPERVISOR_SV (1'b1)
`define ARMLEOCPU_PRIVILEGE_MACHINE (2'b11)



// Decode output bits, semi-one-hot
// Multiple bits can be high at the same time

// Used in decode section
`define ARMLEOCPU_OPCODE_LUI (7'b0110111)
`define ARMLEOCPU_OPCODE_AUIPC (7'b0010111)
`define ARMLEOCPU_OPCODE_JAL (7'b1101111)
`define ARMLEOCPU_OPCODE_JALR (7'b1100111)
`define ARMLEOCPU_OPCODE_BRANCH (7'b1100011)
`define ARMLEOCPU_OPCODE_LOAD (7'b0000011)
`define ARMLEOCPU_OPCODE_STORE (7'b0100011)
`define ARMLEOCPU_OPCODE_OP_IMM (7'b0010011)
`define ARMLEOCPU_OPCODE_OP (7'b0110011)
`define ARMLEOCPU_OPCODE_FENCE (7'b0001111)
`define ARMLEOCPU_OPCODE_SYSTEM (7'b1110011)
`define ARMLEOCPU_OPCODE_AMO (7'b0101111)



`define ARMLEOCPU_DECODE_RD_SEL_WIDTH 3
`define ARMLEOCPU_DECODE_RD_SEL_ALU (`ARMLEOCPU_DECODE_RD_SEL_WIDTH'd0)
`define ARMLEOCPU_DECODE_RD_SEL_MEMORY (`ARMLEOCPU_DECODE_RD_SEL_WIDTH'd1)
`define ARMLEOCPU_DECODE_RD_SEL_LUI (`ARMLEOCPU_DECODE_RD_SEL_WIDTH'd2)
`define ARMLEOCPU_DECODE_RD_SEL_MULDIV (`ARMLEOCPU_DECODE_RD_SEL_WIDTH'd3)
`define ARMLEOCPU_DECODE_RD_SEL_PC_PLUS_4 (`ARMLEOCPU_DECODE_RD_SEL_WIDTH'd4)
`define ARMLEOCPU_DECODE_RD_SEL_STORE_CONDITIONAL_RESULT (`ARMLEOCPU_DECODE_RD_SEL_WIDTH'd5)
`define ARMLEOCPU_DECODE_RD_SEL_CSR (`ARMLEOCPU_DECODE_RD_SEL_WIDTH'd6)

`define ARMLEOCPU_DECODE_INSTRUCTION_WIDTH 5

`define ARMLEOCPU_DECODE_INSTRUCTION_NOP (`ARMLEOCPU_DECODE_INSTRUCTION_WIDTH'd0)
`define ARMLEOCPU_DECODE_INSTRUCTION_ALU (`ARMLEOCPU_DECODE_INSTRUCTION_WIDTH'd1)
`define ARMLEOCPU_DECODE_INSTRUCTION_MULDIV (`ARMLEOCPU_DECODE_INSTRUCTION_WIDTH'd2)
`define ARMLEOCPU_DECODE_INSTRUCTION_JUMP (`ARMLEOCPU_DECODE_INSTRUCTION_WIDTH'd3)
`define ARMLEOCPU_DECODE_INSTRUCTION_BRANCH (`ARMLEOCPU_DECODE_INSTRUCTION_WIDTH'd4)
`define ARMLEOCPU_DECODE_INSTRUCTION_STORE (`ARMLEOCPU_DECODE_INSTRUCTION_WIDTH'd5)
`define ARMLEOCPU_DECODE_INSTRUCTION_LOAD (`ARMLEOCPU_DECODE_INSTRUCTION_WIDTH'd6)
`define ARMLEOCPU_DECODE_INSTRUCTION_LOAD_RESERVE (`ARMLEOCPU_DECODE_INSTRUCTION_WIDTH'd7)
`define ARMLEOCPU_DECODE_INSTRUCTION_STORE_CONDITIONAL (`ARMLEOCPU_DECODE_INSTRUCTION_WIDTH'd8)
`define ARMLEOCPU_DECODE_INSTRUCTION_CACHE_FLUSH (`ARMLEOCPU_DECODE_INSTRUCTION_WIDTH'd9)
`define ARMLEOCPU_DECODE_INSTRUCTION_EBREAK (`ARMLEOCPU_DECODE_INSTRUCTION_WIDTH'd10)
`define ARMLEOCPU_DECODE_INSTRUCTION_ECALL (`ARMLEOCPU_DECODE_INSTRUCTION_WIDTH'd11)
`define ARMLEOCPU_DECODE_INSTRUCTION_CSR (`ARMLEOCPU_DECODE_INSTRUCTION_WIDTH'd12)

`define ARMLEOCPU_DECODE_IN0_MUX_SEL_WIDTH 1
`define ARMLEOCPU_DECODE_IN0_MUX_SEL_RS1 (`ARMLEOCPU_DECODE_IN0_MUX_SEL_WIDTH'd0)
`define ARMLEOCPU_DECODE_IN0_MUX_SEL_PC (`ARMLEOCPU_DECODE_IN0_MUX_SEL_WIDTH'd1)

`define ARMLEOCPU_DECODE_IN1_MUX_SEL_WIDTH 4
`define ARMLEOCPU_DECODE_IN1_MUX_SEL_RS2 (`ARMLEOCPU_DECODE_IN1_MUX_SEL_WIDTH'd0)
`define ARMLEOCPU_DECODE_IN1_MUX_SEL_SIMM12 (`ARMLEOCPU_DECODE_IN1_MUX_SEL_WIDTH'd1)
`define ARMLEOCPU_DECODE_IN1_MUX_SEL_CONST4 (`ARMLEOCPU_DECODE_IN1_MUX_SEL_WIDTH'd2)
`define ARMLEOCPU_DECODE_IN1_MUX_SEL_IMM_JAL_OFFSET (`ARMLEOCPU_DECODE_IN1_MUX_SEL_WIDTH'd3)
`define ARMLEOCPU_DECODE_IN1_MUX_SEL_IMM_BRANCH_OFFSET (`ARMLEOCPU_DECODE_IN1_MUX_SEL_WIDTH'd4)
`define ARMLEOCPU_DECODE_IN1_MUX_SEL_IMM_STORE (`ARMLEOCPU_DECODE_IN1_MUX_SEL_WIDTH'd5)
`define ARMLEOCPU_DECODE_IN1_MUX_SEL_ZERO (`ARMLEOCPU_DECODE_IN1_MUX_SEL_WIDTH'd6)

`define ARMLEOCPU_DECODE_SHAMT_RS2 1'd0
`define ARMLEOCPU_DECODE_SHAMT_IMM 1'd1

`define ARMLEOCPU_PIPELINE_CMD_NONE 2'd0
`define ARMLEOCPU_PIPELINE_CMD_KILL 2'd1
`define ARMLEOCPU_PIPELINE_CMD_FLUSH 2'd2
`define ARMLEOCPU_PIPELINE_CMD_BRANCH 2'd3

`define ARMLEOCPU_ALU_SELECT_WIDTH 4
`define ARMLEOCPU_ALU_SELECT_ADD (`ARMLEOCPU_ALU_SELECT_WIDTH'd0)
`define ARMLEOCPU_ALU_SELECT_SUB (`ARMLEOCPU_ALU_SELECT_WIDTH'd1)
`define ARMLEOCPU_ALU_SELECT_SLT (`ARMLEOCPU_ALU_SELECT_WIDTH'd2)
`define ARMLEOCPU_ALU_SELECT_SLTU (`ARMLEOCPU_ALU_SELECT_WIDTH'd3)
`define ARMLEOCPU_ALU_SELECT_SLL (`ARMLEOCPU_ALU_SELECT_WIDTH'd4)
`define ARMLEOCPU_ALU_SELECT_SRA (`ARMLEOCPU_ALU_SELECT_WIDTH'd5)
`define ARMLEOCPU_ALU_SELECT_SRL (`ARMLEOCPU_ALU_SELECT_WIDTH'd6)
`define ARMLEOCPU_ALU_SELECT_XOR (`ARMLEOCPU_ALU_SELECT_WIDTH'd7)
`define ARMLEOCPU_ALU_SELECT_OR (`ARMLEOCPU_ALU_SELECT_WIDTH'd8)
`define ARMLEOCPU_ALU_SELECT_AND (`ARMLEOCPU_ALU_SELECT_WIDTH'd9)

`define ARMLEOCPU_MULDIV_SELECT_WIDTH 3
`define ARMLEOCPU_MULDIV_SELECT_MUL (`ARMLEOCPU_MULDIV_SELECT_WIDTH'd0)
`define ARMLEOCPU_MULDIV_SELECT_MULH (`ARMLEOCPU_MULDIV_SELECT_WIDTH'd1)
`define ARMLEOCPU_MULDIV_SELECT_MULHSU (`ARMLEOCPU_MULDIV_SELECT_WIDTH'd2)
`define ARMLEOCPU_MULDIV_SELECT_MULHU (`ARMLEOCPU_MULDIV_SELECT_WIDTH'd3)
`define ARMLEOCPU_MULDIV_SELECT_DIV (`ARMLEOCPU_MULDIV_SELECT_WIDTH'd4)
`define ARMLEOCPU_MULDIV_SELECT_DIVU (`ARMLEOCPU_MULDIV_SELECT_WIDTH'd5)
`define ARMLEOCPU_MULDIV_SELECT_REM (`ARMLEOCPU_MULDIV_SELECT_WIDTH'd6)
`define ARMLEOCPU_MULDIV_SELECT_REMU (`ARMLEOCPU_MULDIV_SELECT_WIDTH'd7)