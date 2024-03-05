clear all
close all
clc

%cell and reactor parameters
mu_max=0.0251; %1/h
CM=4; %mg/dL
YGC= 155 * 10^-6; %(mM)/(cell/mL)
Ccellout=0;
V=65.0; % reactor volume, mL
v_cell = 65; %ml
CcMax = 1e10 / V; %max capacity of reactor
CcTarget = 1e10 / V; %cell count target
cell0 = 1e6;
Ccell0= cell0 / v_cell; %initial cell count
OCR = 2.8e-11; %mmol/cell/hour (oxygen)
CO0 = .245; %mmol/liter
%multiplied by 5 for more cell growth
F_fresh_start = 5 * .016 * 60; %ml/hr
F_recycle_start = 5 * 1.1 * 60; %ml/hr
F_net = F_fresh_start + F_recycle_start; %target flowrate to stay at
F_fresh_max = 25; %max fresh flowrate
CG0=185; %mg/dL
F_max = 25; %flowrate at which cells will wash out
cg_noGrowth = 10;

%simulation parameters
ts=1; %sampling time

%system fault controls
freshPump_failure = 0; %detection requires lowConc controllers to be on
recPump_failure = 0;
o2sensor_failure = 0;
glucosesensor_failure = 0;

%cyberattack controls
CG_post_attack = 1;
CG_fake_failure = 0;
CG_ramp_attack = 1;
C0_post_attack = 0;
CO_fake_failure = 0;
CO_ramp_attack = 0;
fresh_attack = 0;
rec_attack = 0;

%countermeasures controls
lowConc_controller_onState = 1; %increases fresh:recycle ratio for low CG/CO
maxFlowrate_controller_onState = 0; %prevents overall flowrate from increasing
minFlowrate_controller_onState = 0; %prevents overall flowrate from decreasing
ratioIncreaser_controller_onState = 0; %prevents fresh flowrate ratio from decreasing
ss_counter_measure = 0; %steady state detection countermeasures
dd_counter_measure = 0; %deviation detection countermeasures
simFlowrate_controller_onState = 0; %switch to simulated sensor values if compromised

%steady state detection parameters
p_thresh = .4; %probability threshold
t_window = 2.5; %time of elements to consider
n_size = t_window/ts;
count_thresh = 3; %times to cross threshold to switch
n_size_CG = n_size;
n_size_Ccell = n_size;
t_crit_CG = .7;
t_crit_Ccell = 1.0;

%system control parameters
CGmin = 50; %CG target and lower bound
CG_target = 50; %target CG for lowConc controller
CO_tolerance = 0; %target o2
CG_thresh = 50; %CG to kick on controller
O_target = CO0 * .5; %oxygen level too low, will kick on controller
buffer = 10; %time to allow other sim to start
actionDelay = 10; %hours to wait between controller actions
CG_increase_rate = 2; %m of y=mx+b
CG_increase_b = 0; %b of y=mx+b

%data processing and fault detection parameters
o2_movingaverage_window = 10; %how many samples to average
o2_movingaverage_delay = 1;  %how many samples to wait
o2_alpha = .20; %exponential weighted average, 0 favors old data, 1 new
o2_fault_halfrange = .01; %expected noise from failed sensor
o2_fault_numpoints = 5; %how many points within range to trigger failure
o2_lownoise_val = .0008; %low end of expected noise of o2 system
o2_prob_arraylen = 10;%number of data points to compute o2 dev prob
o2_prob_thresh = .45; %threshold for o2 probability to be considered deviated
o2_prob_count = 6; %number of data points below prob to trigger deviation
o2_numpoints_low = 6; %number of points to exceed to trigger low noise system
g_standdev_window_size = 15; %window of points to compute noise stdev
g_standev_tol = 7; %stdev of glucose noise
g_numpoints_fail = g_standdev_window_size+1; %how many points outside range to trigger failure
g_prob_arraylen = 15; %number of data points to compute o2 dev prob
g_prob_thresh = .45; %threshold for glucose probability to be considered deviated
g_prob_count = 6; %number of data points below prob to trigger deviation
g_lownoise_val = 1.25; %low end of expected noise of glucose system
g_numpoints_low = 4; %number of points to exceed to trigger low noise system
g_fault_wait_time = 10; %how long to wait after a fault to wait for secondary faults
g_flowrate_control_windowsize = 10; %for process control, how many points to average
freshPump_response_window = 10; %samples to wait for #response_amount increases after increase
freshPump_response_increases = 2; %how many increases are required during window
recPump_rollingavg_samples_buildup = 10; %how many rolling average data points to build up before assessing 
recPump_drop_val = .02; %what constitutes a large drop in rec_pump_flowrate
recPump_smallDrop_size = 0.006; %how big the rolling average must drop to trigger a numDrops increase


%noise control
CG_noise = 1; %1
C0_noise = 1; %1
Ccell_noise = 0;%1 

%noise parameters
np=2;
mean_noise_Ccell = 3.627; %3.627
stdev_noise_Ccell = 11.51; %11.51
mean_noise_CG = 0; %0
stdev_noise_CG = 3.5; %3.5
mean_noise_C0 = 0;
stdev_noise_C0 = .002;
CG_tolerance = .2; %.2
flowrateNoiseActive = 0; %1 = active, 0 = none
flowrateNoiseVal = 0.5 / 100; %percent

%cyberattack parameters
CG_attack_c = 55; %150
CG_post_attack_val = .25; %0
CG_ramp_time = 125; 
CG_attack_time = 175; 
CG_fake_failure_noise = 8;
C0_post_attack_val = -.25; %.8
C0_attack_c = 0;%10
CO_attack_time = 80;
CO_fake_failure_noise = .005;
CO_fake_failure_mean = .08;
CO_ramp_time = 100;
fresh_attack_time = 70;
fresh_attack_val = .1; %ml/hr
rec_attack_time = 50;
rec_attack_val = 120; %ml/hr

%system fault parameters
glucose_fail_noise = 10; 
o2_fail_time = 50;
o2_fail_mean = .008;
o2_fail_noise = .005;
g_failure_start_t = 80; %hours at which to start failure
freshPump_fail_time = 30;
recPump_fail_time = 30;

%Fault codes
%0: no faults detected
%1: O2 sensor failure
%2: glucose sensor failure
%3: recycle pump failure
%4: fresh medium pump failure
%5: glucose sensor disturbance detected
%6: oxygen sensor disturbance detected
%7: system compromised

%cominations imply multiple faults detected
%e.g., 178 = o2 sensor failure, recycle pump hacked, fresh pump hacked

%what faults would cause to happen
%0: regular operation
%1: o2 sensor drops to values +/- noise (o2 stays at low value with no
%flowrate response)
%2: glucose noise goes crazy (find sigma of noise, above threshold)
%3: test
%4: test
%5: deviation from predicted values
%6: deviation from predicted values
%7: test


%%%%%% OLD PARAMETERS %%%%%%%%%%%
%old reactor parameters (unused) 
CCEx = 0; %initial number of exhausted cells
m=0.653; %Lactate
n=0.169; %Ammonium ion
CL_max=84.6; %mM
CA_max=20.4; %mM
YAC= 2*10^-3 * 10^-6; %(mM)/(cell/mL)
YLC= 1 * 10^-6; %(mM)/(cell/mL)
patient_weight = 100; %kg
cells_kilo = 2 * 10^6; %cells per kg patient
CL_target = 40;
CA_target = 10;
CmAb0=0; %mg/dL
CA0=0; %mM
CL0=0; %mg/dL
p=-1.16;%Ammonium ion
q=0.55; %Lactates
o = .3;
YOC = 5e-6;
CO_norm = 21; %normoxic oxygen level
F_start = .05; %ml/min
useCapFunc = 1; %-1 uses the special functon, 1 bypasses
D_start = .05;


%centrifuge parameters (unused)
RPM = 1200;
rho_cells = 1077; %kg/m^3
rho_fluid = 1007; %kg/m^3
diameter_cells = 12*10^-6; %m
u_fluid = .958 * 10^-3; %Pa*s
r_spin = .07; %m
flow_diameter = .02; %m