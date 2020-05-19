`define EXCEPTION_CODE_INTERRUPT (32'h8000_0000)
`define EXCEPTION_CODE_SOFTWATE_INTERRUPT (3 | `EXCEPTION_CODE_INTERRUPT)
`define EXCEPTION_CODE_TIMER_INTERRUPT (7 | `EXCEPTION_CODE_INTERRUPT)
`define EXCEPTION_CODE_EXTERNAL_INTERRUPT (11 | `EXCEPTION_CODE_INTERRUPT)

`define EXCEPTION_CODE_INSTRUCTION_ADDRESS_MISALIGNED (0)
`define EXCEPTION_CODE_INSTRUCTION_ACCESS_FAULT (1)
`define EXCEPTION_CODE_ILLEGAL_INSTRUCTION (2)
`define EXCEPTION_CODE_BREAKPOINT (3)
`define EXCEPTION_CODE_LOAD_ADDRESS_MISALIGNED (4)
`define EXCEPTION_CODE_LOAD_ACCESS_FAULT (5)
`define EXCEPTION_CODE_STORE_ADDRESS_MISALIGNED (6)
`define EXCEPTION_CODE_STORE_ACCESS_FAULT (7)

// Calls from x privilege
`define EXCEPTION_CODE_UCALL (8)
`define EXCEPTION_CODE_SCALL (9)
`define EXCEPTION_CODE_MCALL (11)
`define EXCEPTION_CODE_INSTRUCTION_PAGE_FAULT (12)
`define EXCEPTION_CODE_LOAD_PAGE_FAULT (13)
`define EXCEPTION_CODE_STORE_PAGE_FAULT (15)