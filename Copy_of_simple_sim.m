%% Spacecraft Sim
% the below sim uses the Kane/Levinson quaternion convention. Two vector
% basis are used, N which is fixed to the inertial (newtonian) reference 
% frame, and B which is fixed to the spacecraft reference frame. Attitude 
% is stored as parametrizations of the ^N R ^B direction cosine matrix.

% the script 'Slew_manuever_script.m' has the following features that can
% be migrated over to this one easily:
%
%     - Spline trajectory generation between Modified Rodrigues Parameters
%     - Eigen Axis Slew
%     - Time Variant LQR
%     - LQR Station Keeping 
%     - 3D Gausian noise on attitude/angular velocity 

%% Setup 
clear

% Actuator Jacobians

%% testing region 
% w_rads = [.2 -.3 .5];
% w_max_deg = 50;
% action_space_size = 2*w_max_deg + 1;
% [s] = disc_state(w_rads,w_max_deg)
clear

% tau_max = 5;
% tau = [2.1 3.2 -4.5];
% tau = [-5 -5 -5]
% %action_space_size = 2*tau_max + 1;
% 
% a = disc_action(tau,tau_max)
% tau = tau_from_a(a,tau_max)

%%
rng(1)
% rt is the position vector of each thruster, at is the thrust axis
rt1 = 5*rand(3,1);
at1 = rand(3,1); at1 = at1/norm(at1);
rt2 = 5*rand(3,1);
at2 = rand(3,1); at2 = at2/norm(at2);
rt3 = 5*rand(3,1);
at3 = rand(3,1); at3 = at3/norm(at3);

% thruster actuator jacobian
B_t = [cross(rt1,at1),cross(rt2,at2),cross(rt3,at3)];
invB_t = inv(B_t);

% momentum wheel jacobian
B_w = eye(3);
invB_w = inv(B_w);

% spacecraft inertia properties 
J = diag([100 200 300]);
invJ = diag([1/100 1/200 1/300]);

% timing stuff
samp_rate = 100;                                  % hz
t_f = 50;                                         % s
t_vec = 0:1/samp_rate:(t_f-(1/samp_rate));

% initial conditions 
%q_init = randq;
q_init = ([1 2 3 4]/norm([1 2 3 4]))';
w_initial = deg2rad([30 15 25]);                   % rad/s
init = [q_init', w_initial, 0 0 0,0 0 0,0 0 0];

% allocate arrays 
quat_hist = zeros(4,length(t_vec));
omega_hist = zeros(3,length(t_vec));

% state discritization size


% Q learning Stuff
w_max_deg = 50;
tau_max = 5;
action_space_size = 2*tau_max + 1;
state_space_size = 2*w_max_deg + 1;
Q = zeros(state_space_size^3,action_space_size^3);
N = zeros(state_space_size^3,action_space_size^3);
gamma = .9;


%% Sim
for i = 1:length(t_vec)
    
    %store for graphing 
    quat_hist(:,i) = init(1:4);
    omega_hist(:,i) = init(5:7);
    
    H_N_t = norm(dcm_from_q(quat_hist(:,i))*(J*omega_hist(:,i)));
    % --------------------RL ALG SPOT------------------------------------
    
    s_t = disc_state(init(5:7),w_max_deg);
    
    % epsilon greedy exploration/exploitation
    epsilon = .5;
    random_number = rand;
    
    if random_number < epsilon % go with our Q for best action
        [a_t,~] = max_from_Q(Q,s_t);
    else % go with random action
        a_t = randi(action_space_size^3);
    end
    
    % update N(s,a) count
    N(s_t,a_t ) = N(s_t,a_t ) + 1;
    
    % get control 
    tau = tau_from_a(a_t,tau_max);
    init(8:10) = tau;
    
    
    
    
    % discretize state (angular velocity) to scalar integer
    %s(i) = discretize_state(omega_hist(:,i),disc_size);

    % controller
%     [init] = controller(init,'detumble',B_t,invB_t);
    
    % --------------------RL ALG SPOT------------------------------------
    
    %propagate 1/samp_rate
    [~,y] = ode45(@(t,X) trajODE(t,X,B_w,B_t),[0,1/samp_rate],init);
   
    %reset initial conditions 
    init = y(end,:)';
    
    % s_tp1
    s_tp1 = disc_state(init(5:7),w_max_deg);
    
    H_N_tp1 = norm(dcm_from_q(init(1:4))*(J*init(5:7)));
    totalH(i) = H_N_tp1;
    
    r_t = (H_N_t - H_N_tp1); % reward if we lose angular momentum
    
    alpha = 1/N(s_t,a_t);
    [~,Q_max_stp1] = max_from_Q(Q,s_tp1);
    Q(s_t,a_t) = Q(s_t,a_t) + alpha*(r_t + gamma*Q_max_stp1 - Q(s_t,a_t));
    
      
end

%% Post Processing 

% allocate arrays 
H_B = zeros(3,length(t_vec));
H_N = zeros(3,length(t_vec));

for i = 1:length(t_vec)
    
    % DCM [^N R ^B]
    N_R_B = dcm_from_q(quat_hist(:,i));
    
    % angular momentum expressed in basis b (body fixed)
    H_B(:,i) = J*omega_hist(:,i);
    
    % angular momentum expressed in basis n (inertial)
    H_N(:,i) = N_R_B*H_B(:,i);
    
end


%% Plotting 
figure
hold on 
title('Quaternion')
plot(t_vec,quat_hist(1,:));
plot(t_vec,quat_hist(2,:));
plot(t_vec,quat_hist(3,:));
plot(t_vec,quat_hist(4,:));
legend('q_1','q_2','q_3','q_4')
xlabel('Time (s)')
hold off

figure
hold on 
title('Angular Velocity')
plot(t_vec,rad2deg(omega_hist(1,:)));
plot(t_vec,rad2deg(omega_hist(2,:)));
plot(t_vec,rad2deg(omega_hist(3,:)));
legend('\omega_x','\omega_y','\omega_z')
xlabel('Time (s)')
ylabel('Angular Velocity (deg/s)')
hold off

figure
hold on 
title('Angular Momentum (Expressed in Inertial Basis N)')
plot(t_vec,rad2deg(H_N(1,:)));
plot(t_vec,rad2deg(H_N(2,:)));
plot(t_vec,rad2deg(H_N(3,:)));
legend('H nx','H ny','H nz')
xlabel('Time (s)')
ylabel('Angular Velocity (deg/s)')
hold off

figure
hold on 
plot(t_vec,totalH)
hold off

%% Supporting functions 

function [X_dot] = trajODE(t,X,B_w,B_t)

% spacecraft inertia properties 
J = diag([100 200 300]);
invJ = diag([1/100 1/200 1/300]);

% unpack state 
X = X(:);
quat = X(1:4)/norm(X(1:4));   % quaternion (scalar last, Kane/Levinson)
omega = X(5:7);               % N_w_B rad/s
u = X(8:10);                  % thrust in newtons (1 for each thruster)
rotor = X(11:13);             % rad/s
rotor_dot = X(14:16);         % rad/s^2
%tau = B_t * u;  % n*m
tau = 3*u;

% wheel momentum
rho = B_w*rotor;
rho_dot = B_w*rotor_dot;

% dynamics
X_dot = zeros(size(X));
X_dot(1:4) = .5*qdot(quat,[omega;0]);
X_dot(5:7) = -invJ*(rho_dot + cross(omega,J*omega+rho) - tau);
X_dot(11:13) = rotor_dot;

end

% function [init] = controller(init,mode,B_t,invB_t)
% 
% % unpack state:
% X = init(:);
% quat = X(1:4)/norm(X(1:4));
% omega = X(5:7);
% u = X(8:10);
% rotor = X(11:13);
% rotor_dot = X(14:16);
% tau = B_t * u;
% 
% % spacecraft inertia properties 
% J = diag([100 200 300]);
% invJ = diag([1/100 1/200 1/300]);
% 
% if mode == 'detumble'
%     
%     % get attitude 
%     N_R_B = dcm_from_q(quat);
%     
%     % angular momentums 
%     H_B = J*omega;
%     H_N = N_R_B*H_B;
%     
%     % thrust against the inertial angular momentum
%     max_thrust = 3;
%     tau_out_N = -max_thrust*(H_N/norm(H_N)); 
%     tau_out_B = (N_R_B')*tau_out_N;
%     u_out = (invB_t * tau_out_B)';
%     u_out = saturate(u_out,max_thrust);
%     init(8:10) = u_out;
%     
% end
% 
% end


% function [sat_in] = saturate(sat_in,thresh)
% for i = 1:length(sat_in)
%     if abs(sat_in(i)) > thresh 
%         sat_in(i) = thresh * sign(sat_in(i));
%     end
% end
% end

function [s] = discretize_state(w,disc_size)
% disc_size should be a 1x3 vector

% plus or minus 40 deg/s
w = 1+disc_size/2 + round(rad2deg(w));
if any(w<0) || any(w>disc_size) || any(w<-disc_size)
    error('you screwed something up, we have a negative')
end

s = sub2ind([disc_size,disc_size,disc_size],w(1),w(2),w(3));


end

function [s] = disc_state(w_rads,w_max_deg)
% disc_size should be a 1x3 vector
w = round(rad2deg((w_rads(:))));

for i = 1:length(w)
    if abs((w(i)))>w_max_deg 
        error('outside state space')
    end
end

w = w_max_deg + w + 1;
disc_size = w_max_deg*2 +1;


s = sub2ind([disc_size,disc_size,disc_size],w(1),w(2),w(3));


end

% function [s] = disc_action(w_rads,w_max_deg)
% % disc_size should be a 1x3 vector
% w = round(rad2deg((w_rads(:))));
% 
% for i = 1:length(w)
%     if abs((w(i)))>w_max_deg 
%         error('outside state space')
%     end
% end
% 
% w = w_max_deg + w + 1;
% disc_size = w_max_deg*2 +1;
% 
% 
% s = sub2ind([disc_size,disc_size,disc_size],w(1),w(2),w(3));
% 
% 
% end


% function [w] = undiscretize_state(s,disc_size)
% 
% [wx,wy,wz] = ind2sub([disc_size,disc_size,disc_size],s);
% 
% w = [wx,wy,wz];
% 
% w = deg2rad(w - disc_size/2 - 1);
% 
% % TEST
% % w = [-.7 .3 -.1]
% % disc_size = 80; % this means -40 to 40 
% % [s] = discretize_state(w,disc_size);
% % [w] = undiscretize_state(s,disc_size)
% end


function [a,Q_max] = max_from_Q(Q,s)
% returns max Q, and argmax Q for a given state

% row of interest 
vec = Q(s,:);

% maximum Q in the row
Q_max = max(vec);

% find list of actions that produce this Q max
a_list = find(vec == Q_max);

% if there is a tie, or all zeros, choose a random
if length(a_list) > 1
    a = a_list(randi(length(a_list)));
else
    a = a_list(1);
end
end

function tau = tau_from_a(a,tau_max)
% gets control input tau from action a

action_space_size = 2*tau_max + 1;

[taux,tauy,tauz] = ind2sub([action_space_size,action_space_size,action_space_size],a);

tau = [taux;tauy;tauz];
tau = tau - tau_max - 1;


end

function [a] = disc_action(tau,tau_max)
% disc_size should be a 1x3 vector
tau = round(tau(:));

for i = 1:length(tau)
    if abs((tau(i)))>tau_max 
        error('outside action space')
    end
end

tau = tau_max + tau + 1;
disc_size = tau_max*2 +1;


a = sub2ind([disc_size,disc_size,disc_size],tau(1),tau(2),tau(3));


end
