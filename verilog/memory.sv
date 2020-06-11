//--------------
// Dual Port RAM
//--------------

`ifndef MEM_WIDTH
  `define MEM_WIDTH 16
`endif
`ifndef MEM_SIZE
  `define MEM_SIZE 16
`endif
`ifndef MEM_MAX_ADDR
  `define MEM_MAX_ADDR 4
`endif

module memory (
  //Output
  data_out,

  //Input
  data_in,
  addr,
  we,
  Clock,
  nReset
);

timeunit 1ns;
timeprecision 100ps;

output [`MEM_WIDTH-1:0] data_out [1:0];

input [`MEM_WIDTH-1:0] data_in [1:0];
input [`MEM_MAX_ADDR-1:0] addr [1:0];
input we [1:0];
input Clock;
input nReset;

reg [`MEM_WIDTH-1:0] mem [`MEM_SIZE-1:0];
//mem0=Odometer_l
//mem1=Odometer_h
//mem2=Trip timer
//mem3=Speedometer
//mem4=Cadence Meter

integer j;

always_ff @(posedge Clock or negedge nReset)
if(!nReset) begin
  for (j=0; j < `MEM_WIDTH; j=j+1) begin
    mem[j] <= 16'b0; //reset array
  end
end
else
  if (we[0]) begin
    mem[addr[0]] <= data_in[0];
    //$display("Port 0 writing %d to memory at address %d", data_in[0], addr[0]);
  end 
  else 
    if (we[1]) begin
      mem[addr[1]] <= data_in[1];
      //$display("Port 1 writing %d to memory at address %d", data_in[1], addr[1]);
    end
    else
      mem <= mem;

assign data_out[0] = mem[addr[0]];
assign data_out[1] = mem[addr[1]];

endmodule
