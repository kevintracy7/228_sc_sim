%% Spacecraft Sim
% the below sim uses the Kane/Levinson quaternion convention. Two vector
% basis are used, N which is fixed to the inertial (newtonian) reference 
% frame, and B which is fixed to the spacecraft reference frame. Attitude 
% is stored as parametrizations of the ^N R ^B direction cosine matrix.

% the script 'Slew_manuever_script.m' has the following features that can
% be migrated over to this one pretty easily:
%
%     - Spline trajectory generation between Modified Rodrigues Parameters
%     - Eigen-Axis Slew
%     - Time Variant LQR
%     - LQR Station Keeping 
%     - 3D Gausian noise on attitude/angular velocity 

%% Setup 
clear

% Actuator Jacobians
rng(2)
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
J_measured = J;%J*expm(hat(.05*randn(3,1)));

% timing stuff
samp_rate = 100;                                  % hz
t_f = 200;                                         % s
t_vec = 0:1/samp_rate:(t_f-(1/samp_rate));

% initial conditions 
q_init = randq;
w_initial = deg2rad([30 15 -25]);                   % rad/s
init = [q_init', w_initial, 0 0 0,0 0 0,0 0 0];

% allocate arrays 
quat_hist = zeros(4,length(t_vec));
omega_hist = zeros(3,length(t_vec));

% noise
%V_quat = .1*eye(3);

% Q learning Stuff
w_max_deg = 50;
tau_max = 5;
action_space_size = 2*tau_max + 1;
state_space_size = 2*w_max_deg + 1;
Q = zeros(state_space_size^3,action_space_size^3);
N = zeros(state_space_size^3,action_space_size^3);
gamma = .9;
H_B_t = zeros(1,length(t_vec));

for kk = 1:100
    init = [q_init', w_initial, 0 0 0,0 0 0,0 0 0];
%% Sim
for i = 1:length(t_vec)
    
    % store for graphing 
    quat_hist(:,i) = init(1:4);
    omega_hist(:,i) = init(5:7);
    
    % angular momentum at time t
    H_B_t(i) = norm((J_measured*omega_hist(:,i)));

    % discretized state s_t
    s_t = disc_state(init(5:7),w_max_deg);
    
    % epsilon greedy exploration/exploitation
    epsilon = .2;
    random_number = rand;
    
    if random_number < epsilon % go with our Q for best action
        [a_t,~] = max_from_Q(Q,s_t);
    else % go with random action
        a_t = randi(action_space_size^3);
    end
    
    % check to see if i've done the action before 
    if sum(N(s_t,a_t)>0) == length(N(s_t,a_t )) % this means i've tried them all 
        [a_t,~] = max_from_Q(Q,s_t);
    end
    
    % update N(s,a) count
    N(s_t,a_t ) = N(s_t,a_t ) + 1;
    
    % get tau from a 
    tau = tau_from_a(a_t,tau_max);
    init(8:10) = tau;
    
    % propagate 1/samp_rate
    [~,y] = ode45(@(t,X) trajODE(t,X,B_w,B_t),[0,1/samp_rate],init);
   
    % reset initial conditions 
    init = y(end,:)';
    
    % s_tp1
    s_tp1 = disc_state(init(5:7),w_max_deg);
    
    % reward 
    H_B_tp1 = norm((J_measured*init(5:7)));
    r_t = (H_B_t(i) - H_B_tp1); % reward if we lose angular momentum
    
    % Q learning Update
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

H_cell{kk} = H_N;

end

%% animation 






% for i = 1:length(quat_hist)
%     
%     [r,p,y] = quat2angle([quat_hist(4,i)' ,quat_hist(1:3,i)'] );
%     
%     simdata(i,:) = [2*t_vec(i), 0,0,0,r,p,y];
%     
%     
%     
%     
% end
% 
% 
% h = Aero.Animation;
% h.FramesPerSecond = 10;
% h.TimeScaling = 5;
% idx1 = h.createBody('pa24-250_orange.ac','Ac3d');
% %load simdata;
% h.Bodies{1}.TimeSeriesSource = simdata;
% h.show();
% h.play();

%% Plotting 
% figure
% hold on 
% title('Quaternion')
% plot(t_vec,quat_hist(1,:));
% plot(t_vec,quat_hist(2,:));
% plot(t_vec,quat_hist(3,:));
% plot(t_vec,quat_hist(4,:));
% legend('q_1','q_2','q_3','q_4')
% xlabel('Time (s)')
% hold off
% 
% figure
% hold on 
% title('Angular Velocity')
% plot(t_vec,rad2deg(omega_hist(1,:)));
% plot(t_vec,rad2deg(omega_hist(2,:)));
% plot(t_vec,rad2deg(omega_hist(3,:)));
% legend('\omega_x','\omega_y','\omega_z')
% xlabel('Time (s)')
% ylabel('Angular Velocity (deg/s)')
% hold off

% figure
% hold on 
% title('Angular Momentum (Expressed in Inertial Basis N)')
% plot(t_vec,rad2deg(H_N(1,:)));
% plot(t_vec,rad2deg(H_N(2,:)));
% plot(t_vec,rad2deg(H_N(3,:)));
% legend('H nx','H ny','H nz')
% xlabel('Time (s)')
% ylabel('Angular Momentum (kg m^2/s)')
% hold off

% figure
% hold on 
% plot(t_vec,H_B_t,'Color',[1 0 0])
% hold off

figure
hold on 
title('Q-Learning Spacecraft Reaction Wheel Detumble (100 Trials)')

% rgb1 = [117 58 136]/255;
% rgb2 = [204 43 94]/255;
% rgb1 = [220 36 48]/255;
% rgb2 = [123 67 151]/255;
rgb1 = [29 38 113]/255;
rgb2 = [195 55 100]/255;
for kk = 1:length(H_cell)
%     if kk <=50
%         rgb_vec = [255,5.1*kk,0]/255;
%     else
%         rgb_vec = [255 - (kk-50)*5.1,255,0]/255;
%     end
%     

rgb_vec = color_interp(rgb1,rgb2,length(H_cell),kk);
    
    
    
plot(t_vec,rad2deg(H_cell{kk}(1,:)),'Color',rgb_vec);
plot(t_vec,rad2deg(H_cell{kk}(2,:)),'Color',rgb_vec);
plot(t_vec,rad2deg(H_cell{kk}(3,:)),'Color',rgb_vec);
end

h(1) = plot(NaN,NaN,'Color',rgb1);
h(2) = plot(NaN,NaN,'Color',rgb2);
%legend(h, 'Run 1','Run 100');
[~,hObj]=legend(h, 'Run 1','Run 100');           % return the handles array
hL=findobj(hObj,'type','line');  % get the lines, not text
set(hL,'linewidth',6) 

%legend('H nx','H ny','H nz')
xlabel('Time (s)')
ylabel('Angular Momentum (kg m^2/s)')
hold off
%saveas(gcf,'detumble_wheel.eps','epsc')




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
%rotor_dot = X(14:16);  
rotor_dot = B_w*u ;             % rad/s^2
%tau = B_t * u;                % n*m
tau = [0;0;0];

% wheel momentum
rho = B_w*rotor;
rho_dot = B_w*rotor_dot;

% dynamics
X_dot = zeros(size(X));
X_dot(1:4) = .5*qdot(quat,[omega;0]);
X_dot(5:7) = -invJ*(rho_dot + cross(omega,J*omega+rho) - tau);
X_dot(11:13) = rotor_dot;

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

function noisy_quat = quat_noise(quat,V_quat)

%noise 
phi_noise = mvnrnd([0 0 0],V_quat)';
q_noise = q_from_phi(phi_noise);


noisy_quat = qdot(q_noise,quat);

end


function rgb_kk = color_interp(rgb1,rgb2,total_kk,kk)

delta_rgb = rgb2-rgb1;

rgb_kk = rgb1 + (kk/total_kk)*delta_rgb;

end