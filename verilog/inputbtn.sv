module inputbtn (
   input Clock,
   input nReset,
   input nTrip,
   input nMode,
   output logic[2:0] mode,
   output logic trip_Reset,
   output logic wheelsize_digit_change,
   output logic wheelsize_value_change,
   output logic wheelsize_menu
);

timeunit 1ns;
timeprecision 100ps;

logic wheelsize_menu_trigger;
wire wheelsize_exit;
logic[3:0]mode_press;
logic modebtn_trigger;
logic tripbtn_trigger;
logic mode_pulse_control_trig;
logic trip_pulse_control_trig;
logic mode_control,trip_control;
logic mode_change,trip_change;

//mode-change
always_ff @(posedge Clock, negedge nReset)
if(!nReset)begin
    mode<=0;
    wheelsize_digit_change<='0;
end
else if(mode==6)
   mode<=0;
else if(mode_change && (!trip_change))
   if(wheelsize_menu) begin
   	mode<=0;
   	wheelsize_digit_change<='1;
   end
   else
   	mode<=mode+1;
else begin
   mode<=mode;
   wheelsize_digit_change<='0;
end

//trip-button
always_ff @(posedge Clock, negedge nReset)
if(!nReset) begin
   trip_Reset<=0;
   wheelsize_value_change<='0;
end
else if(trip_change && (!mode_change)) begin
   if(wheelsize_menu) begin
   	trip_Reset<=0;
	wheelsize_value_change<='1;
   end
   else
   	trip_Reset<=1;
end
else begin
   trip_Reset<=0;
   wheelsize_value_change<='0;
end

//Enter-wheelsize-menu
always_ff @(posedge Clock,negedge nReset)
if(!nReset)
   wheelsize_menu<='0;
else if(wheelsize_menu_trigger)
   wheelsize_menu<='1;
else if (wheelsize_exit)
   wheelsize_menu<='0;
else
   wheelsize_menu<=wheelsize_menu;

//wheelsize-menu-control-button
always_ff @(posedge Clock, negedge nReset)
if(!nReset)
   mode_press<=0;
else if (wheelsize_exit)
   mode_press<=0;
else if(wheelsize_digit_change)
   mode_press<=mode_press+1;

//Pulse capture Timer
logic [12:0] time_count;
always_ff @(posedge Clock, negedge nReset)
if(!nReset)
   time_count<=0;
else if(time_count==5120)
   time_count<=0;
else if((mode_pulse_control_trig || trip_pulse_control_trig) && time_count==0)
   time_count<=1;
else if(time_count==0)
   time_count<=time_count;
else
   time_count<=time_count+1;

//Sync Mode pulse control
always_ff @ (posedge Clock, negedge nReset)
if(!nReset)
   mode_control<=0;
else if (time_count==5120)
   mode_control<=0;
else if((modebtn_trigger)&&(time_count!=5120))
   mode_control<='1;
else
   mode_control<=mode_control;

//Sync Trip pulse control
always_ff @ (posedge Clock, negedge nReset)
if(!nReset)
   trip_control<=0;
else if (time_count==5120)
   trip_control<=0;
else if((tripbtn_trigger)&&(time_count!=5120))
   trip_control<='1;
else 
   trip_control<=trip_control;

//Button Behaviour Capture within 400ms
always_ff @(posedge Clock, negedge nReset)
if(!nReset)begin
   mode_change<='0;
   trip_change<='0;
   wheelsize_menu_trigger<='0;
end
else if(time_count==5119)begin
   if((mode_control)&&(!trip_control))
	mode_change<='1;
   else if((!mode_control)&&(trip_control))
        trip_change<='1;
   else if((mode_control)&&(trip_control))
	wheelsize_menu_trigger<='1;
   else begin
	   mode_change<=mode_change;
           trip_change<=trip_change;
           wheelsize_menu_trigger<=wheelsize_menu_trigger;
   end      
end
else begin
   mode_change<='0;
   trip_change<='0;
   wheelsize_menu_trigger<='0;
end
   

//Mode button time trigger capture
always_ff @(posedge Clock, negedge nReset)
if(!nReset)
   mode_pulse_control_trig<='0;
else
   case(mode_pulse_control_trig)
      0: begin
	 if(!nMode)
	     mode_pulse_control_trig <='1;
         end
      1: begin
	 if(nMode)
	     mode_pulse_control_trig <='0;
         end
   endcase

//Trip button time trigger capture
always_ff @(posedge Clock, negedge nReset)
if(!nReset)
   trip_pulse_control_trig<='0;
else
   case(trip_pulse_control_trig)
      0: begin
	 if(!nTrip)
	     trip_pulse_control_trig <='1;
         end
      1: begin
	 if(nTrip)
	     trip_pulse_control_trig <='0;
         end
   endcase

//button behaviour assignment
assign modebtn_trigger = (!nMode)&&(!mode_pulse_control_trig);
assign tripbtn_trigger = (!nTrip)&&(!trip_pulse_control_trig);

//Exit Wheelmenu Trigger
assign wheelsize_exit=(mode_press==12);

endmodule
