module inputCycle (
   input Clock,nReset,
   input nFork,nCrank,
   output logic[15:0]fork_time,crank_time,
   output logic wheelrev_trigger,
   output logic second_trigger
);

timeunit 1ns;
timeprecision 100ps;

logic[15:0] forktime_count,cranktime_count;
logic fork_clear,crank_clear;
logic[13:0] time_count;
logic forkcycle_pulse_control_trig;
logic crankcycle_pulse_control_trig;
logic forktime_count_overlimit;
logic cranktime_count_overlimit;
logic second_ready;

//Fork
//forktime trigger capture
always_ff @(posedge Clock, negedge nReset)
if(!nReset)
   forkcycle_pulse_control_trig<='0;
else
   case(forkcycle_pulse_control_trig)
      0: begin
	 if(!nFork)
	     forkcycle_pulse_control_trig <='1;
         end
      1: begin
	 if(nFork)
	     forkcycle_pulse_control_trig <='0;
         end
      default:begin
	 if(!nFork)
	     forkcycle_pulse_control_trig <='1;
         end
   endcase

//forktime_counter
always_ff @(posedge Clock ,negedge nReset)
if((!nReset))
   forktime_count<=0;
else if (fork_clear)
   forktime_count<=0;
else if(!forktime_count_overlimit)
   forktime_count<=forktime_count+1;
else 
   forktime_count<=forktime_count;

//Forktime_overlimit_signal
always_ff @(posedge Clock ,negedge nReset)
if(!nReset)
   forktime_count_overlimit<='0;
else if(cranktime_count==63999)
   forktime_count_overlimit<='1;
else if(crank_clear)
   forktime_count_overlimit<='0;
else
   forktime_count_overlimit<=forktime_count_overlimit;

//forktime_output_trigger
always_ff @(posedge Clock, negedge nReset)
if(!nReset)
   fork_time<=0;
else if((!nFork)&&(!forktime_count_overlimit)&&(!forkcycle_pulse_control_trig))
   fork_time<=forktime_count;
else if((!nFork)&&(forktime_count_overlimit)&&(!forkcycle_pulse_control_trig))
   fork_time<=0;
else
   fork_time<=fork_time;
  
logic count_fork_clear;
//forktime_counter_clear
always_ff @(posedge Clock , negedge nReset)
if(!nReset)begin
   fork_clear<='0;
   count_fork_clear<='0;
end
else if((!nFork)&&(forkcycle_pulse_control_trig)) begin
   if(count_fork_clear==0) begin
   fork_clear<='1;
   count_fork_clear<='1;
   end
   else
      fork_clear<='0;
end
else begin
   fork_clear<='0;
   count_fork_clear<='0;
end


//Crank
//cranktime trigger capture
always_ff @(posedge Clock, negedge nReset)
if(!nReset)
   crankcycle_pulse_control_trig<='0;
else
   case(crankcycle_pulse_control_trig)
      0: begin
	 if(!nCrank)
	     crankcycle_pulse_control_trig <='1;
         end
      1: begin
	 if(nCrank)
	     crankcycle_pulse_control_trig <='0;
         end
   endcase

//Cranktime_overlimit
always_ff @(posedge Clock ,negedge nReset)
if(!nReset)
   cranktime_count_overlimit<='0;
else if(cranktime_count==63999)
   cranktime_count_overlimit<='1;
else if(crank_clear)
   cranktime_count_overlimit<='0;
else
   cranktime_count_overlimit<=cranktime_count_overlimit;

//cranktime output trigger
always_ff @(posedge Clock ,negedge nReset)
if((!nReset))
   cranktime_count<=0;
else if ((crank_clear))
   cranktime_count<=0;
else if(cranktime_count_overlimit)
   cranktime_count<=cranktime_count;
else
   cranktime_count<=cranktime_count+1;

//cranktime_send
always_ff @(posedge Clock ,negedge nReset)
if(!nReset)
   crank_time<=0;
else if((!nCrank)&&(!cranktime_count_overlimit)&&(!crankcycle_pulse_control_trig))
   crank_time<=cranktime_count;
else if((!nCrank)&&(cranktime_count_overlimit)&&(!crankcycle_pulse_control_trig))
   crank_time<=0;
else
   crank_time<=crank_time;

logic count_crank_clear;
//crank_clear
always_ff @(posedge Clock , negedge nReset)
if(!nReset)begin
   crank_clear<='0;
   count_crank_clear<='0;
end
else if((!nCrank)&&(crankcycle_pulse_control_trig)) begin
   if(count_crank_clear==0) begin
   crank_clear<='1;
   count_crank_clear<='1;
   end
   else
      crank_clear<='0;
end
else begin
   crank_clear<='0;
   count_crank_clear<='0;
end

//time-trigger-reg
always_ff @ (posedge Clock, negedge nReset)
if(!nReset)
   second_ready='0;
else if(time_count==12799)
   second_ready='1;
else
   second_ready='0;


//Time-trigger
always_ff @(posedge Clock, negedge nReset)
if((!nReset))
   time_count<=0;
else if ((forktime_count_overlimit))
   time_count<=0;
else if (second_trigger)
   time_count<=0;
else
   time_count<=time_count+1;

assign wheelrev_trigger = fork_clear;
assign second_trigger = second_ready;

endmodule
