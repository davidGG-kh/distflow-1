function varargout = distflow_multi(bus, branch, opt)
%%%
%%%		[bus, branch] = distflow_multi(bus, branch, opt)
%%%   [Beta, K, zeta, eta, v0, conn] = distflow_multi(bus, branch, opt)
%%%		
%%%		bus is an nx1 structure array with fields
%%%			- vref scalar reference voltage magnitude (p.u.) (source is
%%%				assumed to be 3 phase balanced)
%%%			- phase  a vector containing phases on bus. e.g [1,2] if only phases 1 and 2 are present.
%%%			- sy phase x 1 vector of per unit Y connected constant power load (complex).
%%%			- sd 3x1 vector of delta connected constant power load. (if none can also be a scalar 0).
%%%			- yy phasex1 vector of of Wye connected constant admittance load.
%%%			- yd 3x1 vector of delta connected constant admittance load
%%%			 	order is [ab, bc, ca].
%%%			- Ysh phase x phase vector of Shunt admittance at bus (for example, 1/2 of branch capacitance).
%%%		
%%%		branch is a n-1x1 structre array with fields
%%%			- f  node id of from node
%%%			- t  node id of to node
%%%			- phase a vector containing the phases of the branch.
%%%			- Z phase x phase matrix of branch impedance (complex).
%%%		
%%%		opt (optiona) options structure with fields:
%%%			- alpha_method loss parametrization method
%%%					 method #    Description
%%%					 --------    -----------
%%%							1				 scalar constant alpha (use this with alpha=0.5 for lossless approximation, default)
%%%					    2        DEPRECATED
%%%					    3        Not Recommended: alpha interpolated linearly based on branch impedance magnitude
%%%					    4        Not Recommended: alpha interpolated quadratically based on branch impedance magnitude
%%%					    5        Not Recommended: alpha interpolated linearly based on branch downstream mva magnitude
%%%					    6        Not Recommended: alpha interpolated quadratically based on branch downstream mva magnitude
%%%					    7        Not Recommended: alpha (per phase) interpolated linearly based on branch impedance
%%%					    8        Not Recommended: alpha (per phase) interpolated quadratically based on branch impedance
%%%					    9        Not Recommended: alpha (per phase) interpolated linearly based on branch downstream mva magnitude
%%%					   10        Not Recommended: alpha (per phase) interpolated quadratically based on branch downstream mva magnitude
%%%						 11        alpha = Diag(m)*(S*z^H)^H(S*z^H) + b
%%%						 12        alpha = Diag(m)*(z*z^H) + b
%%%			- alpha if alpha_method=1 scalar value
%%%							else [alpha_min, alpha_max] the range into which the parameter should be mapped.
%%%			- mats_gen bool
%%%                     false (default) The distflow is performed and updated bus and branch structures returned
%%%                     true  matrices returned so that the solution can be solved independently/repeatedly outside the function:
%%%                                       nu = (Beta*conn.M - K)\(Beta*conn.M*v0 + zeta*sigma + eta*conj(sigma));
%%%                                       v  = sqrt(real(conn.U*nu));
%%%                           NOTE: this is really only intended to be used with alpha_method=12 or 1
%%%
%%% OUPTUT
%%% 	bus.vm 		phase x 1 vector of voltage magnitude
%%%   branch.S	phase x 1 vector of branch apparent power flow (complex)


a = exp(-1i*2*pi/3);
avect = [1; a; a^2];
idx = reshape(1:9,3,3);
if nargin < 3
    opt = [];
end
opt = optdefaults(opt);

if nargin == 0
    %%% Demo
    %%% a1 ---- b1 ----- c1
    %%% a2 ---- b2 ----- c2 ----- e2
    %%% a3 ---- b3
    %%%    \--------d3
    
    zself = 0.01 +1i*0.1;
    zmut  = zself/2;
    zsamp = zmut*ones(3,3);
    zsamp(diag(idx)) = zself;
    nphasing = {[1,2,3], [1,2,3], [1,2], 3, 2}.';
    ephasing = nphasing(2:end);
    zarray   = cellfun(@(x) zsamp(x,x), ephasing,'UniformOutput', false);

    branch   = struct('f', {1, 2, 1, 3}.', 't', {2, 3, 4, 5}.', ...
    'Z', zarray, 'phase', ephasing);
    
    bus      = struct('phase', nphasing, ...
                      'sy', {[0 0 0].', [1 0.9, 1.1].', [0.25 0.25].', 0.1, 0.3}.',...
                      'yd', {[0 0 0].', 0 , [1/(1+1i*0.2), 0, 0].', 0, 0}.',...
                      'vref', 1.02);
    
else
    ephasing = {branch.phase}.';
    nphasing = {bus.phase}.';
end

if ~opt.mats_gen && (nargout~=3)
	error('distflow_multi: Output argument error. Number of outputs with opt.mat_gen=0 must be 2')
elseif opt.mats_gen && (nargout~=6)
	error('distflow_multi: Output argument error. Number of outputs with opt.mat_gen=1 must be 6')
end

%% form matrices
vref = bus(1).vref*avect;
conn = connmats(bus,branch);
sigma = getsigma(bus);
Zconj = cellfun(@conj , {branch.Z},'UniformOutput', false);
if ~isfield(branch, 'Y')
    Y    = cellfun(@(x) inv(x), {branch.Z}, 'UniformOutput', false);
else
    Y = {branch.Y};
end
Yconj= cellfun(@conj, Y, 'UniformOutput', false);
% [branch.Zc] = tmp{:};
v0   = v0vec(vec(vref*vref'), ephasing);
switch opt.gamma_method
    case 1
        zeta = kdiag(Zconj, 'eye', ephasing)*conn.B*conn.TE*kdiag('eye','gamma',nphasing(2:end));
        eta  = kdiag('eye', {branch.Z}, ephasing) *conn.B*conn.TE*kdiag('gammac','eye',nphasing(2:end));
    case 2
        bustmp = distflow_multi(bus,branch,opt.bustmpopt);
%         bustmp = bus;
%         [g, gc] = branchgamma(conn, sigma, Zconj, ephasing);
        [g, gc] = branchgamma(bustmp, branch);
        zeta = kdiag(Zconj, 'eye', ephasing)*conn.B*conn.TE*kdiag('eye',g,nphasing(2:end));
        eta  = kdiag('eye', {branch.Z}, ephasing) *conn.B*conn.TE*kdiag(gc,'eye',nphasing(2:end));
end
if isfield(bus, 'yd') || isfield(bus, 'Ysh')
    [yl, ylc] = yload(bus);
    K = kdiag(Zconj, 'eye', ephasing)*conn.B*conn.TE*kdiag(yl, 'eye', nphasing(2:end)) + ...
        kdiag('eye', {branch.Z}, ephasing)*conn.B*conn.TE*kdiag('eye', ylc, nphasing(2:end));
else
    K = 0;
end

switch opt.alpha_method
    case 1
        if length(opt.alpha) ~= 1
            error('distflow_multi: when using alpha_method 1 the value for alpha must be a scalar.')
        end
        Gamma = kdiag(Zconj, 'eye', ephasing)*(conn.B - conn.I)*kdiag(Yconj, 'eye', ephasing) + ...
                kdiag('eye', {branch.Z}, ephasing)*(conn.B - conn.I)*kdiag('eye', Y, ephasing);
        Beta  = 2*opt.alpha*conn.I - (1-2*opt.alpha)*Gamma;
%     case 2 DEPRECATED
%         if length(opt.alpha) ~= 1
%             error('distflow_multi: when using alpha_method 2 the value for alpha must be a scalar.')
%         end
%         alphavect = 0.5*ones(conn.E,1);
%         alphavect(logical(sum(conn.U,1))) = opt.alpha;
%         alphaDiag = sparse(1:conn.E, 1:conn.E, alphavect, conn.E, conn.E);
%         
%         Gamma = kdiag(Zconj, 'eye', ephasing)*(conn.B - conn.I)*kdiag(Yconj, 'eye', ephasing) + ...
%                 kdiag('eye', {branch.Z}, ephasing)*(conn.B - conn.I)*kdiag('eye', Y, ephasing);
%         Beta = 2*alphaDiag*conn.I - (conn.I - 2*alphaDiag)*Gamma;
    case {3,4,5,6,7,8,9,10,11,12}
        if (length(opt.alpha) ~= 2) && (opt.alpha_method ~= 11) 
          warning('distflow_multi: when using alpha_method 3-6 opt.alpha should contain [alpha_min alpha_max] but a vector of length %d was given.\n', length(opt.alpha))
        end
        if ismember(opt.alpha_method, [3,4,7,8])
          maxx = max(cellfun(@(x) max(abs(diag(x))), {branch.Z}));
          minx = min(cellfun(@(x) min(abs(diag(x))), {branch.Z}));
        elseif ismember(opt.alpha_method, [5,6,9,10])
          sdp  = vect2cell(conn.U*conn.B*conn.TE*sigma, ephasing);
          maxx = max(cellfun(@(x) full(max(abs(x))), sdp));
          minx = min(cellfun(@(x) full(min(abs(x))), sdp));
        elseif opt.alpha_method == 11
          sdp  = vect2cell(conn.U*conn.B*conn.TE*sigma, ephasing);
          sdp  = cellfun(@(x,y) gamma_phi(y)*diag(x), sdp, ephasing, 'UniformOutput', false); 
          dSzh2  = cellfun(@(x,y) diag((x*y')'*(x*y')), sdp, {branch.Z}.', 'UniformOutput', false);
          tmp  = cellfun(@(x,y) full(sparse(y,1,x,3,1)), dSzh2, ephasing, 'UniformOutput', false);
          maxx = max(cat(2, tmp{:}),[], 2);
          tmpind = (1:3).';
          tmp  = cellfun(@(x,y) ...
            full(sparse([y;tmpind(~ismember(tmpind,y))],1,...
                [x;inf(3-length(x),1)],3,1)), dSzh2, ephasing, 'UniformOutput', false);
          minx = min(cat(2, tmp{:}),[],2);
%           maxx = max(cellfun(@(x) max(x), dSzh2));
%           minx = min(cellfun(@(x) min(x), dSzh2));
        elseif opt.alpha_method == 12
          dSzh2  = cellfun(@(x) diag(x*x'), {branch.Z}.', 'UniformOutput', false);
          tmp  = cellfun(@(x,y) full(sparse(y,1,x,3,1)), dSzh2, ephasing, 'UniformOutput', false);
          maxx = max(cat(2, tmp{:}),[], 2);
          tmpind = (1:3).';
          tmp  = cellfun(@(x,y) ...
            full(sparse([y;tmpind(~ismember(tmpind,y))],1,...
                [x;inf(3-length(x),1)],3,1)), dSzh2, ephasing, 'UniformOutput', false);
          minx = min(cat(2, tmp{:}),[],2);
        end
        if ismember(opt.alpha_method, [3,5,7,9,11,12])
            slope = (opt.alpha(end) - opt.alpha(1))./(minx - maxx);
            intercept = opt.alpha(end) - slope.*minx;
        elseif ismember(opt.alpha_method, [4,6,8,10])
            slope = (opt.alpha(end) - opt.alpha(1))/(minx^2 - maxx^2);
            intercept = opt.alpha(end) - slope*minx^2;
        end
%         if ismember(opt.alpha_method, 7:10)
            ydalpha = cell(length(branch),1);
            ycalpha = cell(length(branch),1);
%         else
%             dalpha = cell(length(branch),1);
%         end
        for k = 1:length(branch)
%             dalpha{k} = eye(length(branch(k).phase)) - 2*diag(opt.alpha(1) + slope*(abs(diag(branch(k).Z)) - maxz));
            switch opt.alpha_method
              case {3,4}
                x = max(abs(diag(branch(k).Z)));
              case {5,6}
                x = max(abs(sdp{k}));
              case {7,8}
                x = abs(diag(branch(k).Z));
              case {9,10}
                x = abs(sdp{k});
              case {11,12}
                x = dSzh2{k};
            end
            if ismember(opt.alpha_method, [4,6,8,10])
                x = x.^2;
            end
            if ismember(opt.alpha_method, 3:6)
%                 dalpha{k} = (1 - 2*(slope*x + intercept))*eye(length(branch(k).phase));
                ydalpha{k} = Y{k}*(1 - diag(slope*x + intercept))*eye(length(branch(k).phase));
                ycalpha{k} = Yconj{k}*diag(slope*x + intercept)*eye(length(branch(k).phase));
            elseif ismember(opt.alpha_method, 7:10)
%                 dalpha{k} = eye(length(branch(k).phase)) - 2*diag(slope*x + intercept);
                ydalpha{k} = Y{k}*(eye(length(branch(k).phase)) - diag(slope*x + intercept));
                ycalpha{k} = Yconj{k}*diag(slope*x + intercept);
            elseif ismember(opt.alpha_method, [11,12])
%               atmp = 0.5 - opt.alpha*x;
%               if any(atmp <= 0) || any(atmp >= 1)
%                 disp(atmp);
%               end
%               atmp(atmp<=0) = 0.5;
%               atmp(atmp>=1) = 0.5;
              atmp = slope(ephasing{k}).*x + intercept(ephasing{k});
%               atmp = slope.*x + intercept;
%               atmp = 0.5*(1 - x);
%               atmp(atmp > max(opt.alpha)) = max(opt.alpha);
%               atmp(atmp < min(opt.alpha)) = min(opt.alpha);
              ydalpha{k} = Y{k}*(eye(length(branch(k).phase)) - diag(atmp));
              ycalpha{k} = Yconj{k}*diag(atmp);
            end
        end
%         if ismember(opt.alpha_method, 7:10)
            C = kdiag(Zconj, 'eye', ephasing)*(conn.B - conn.I)*kdiag('eye',{branch.Z},ephasing) +...
            kdiag('eye', {branch.Z}, ephasing)*(conn.B - conn.I)*kdiag(Zconj,'eye', ephasing) +...
            kdiag(Zconj,{branch.Z}, ephasing);
            Gamma = C*(kdiag(Yconj, ydalpha, ephasing) - kdiag(ycalpha, Y, ephasing));
%         else
%             Gamma = kdiag(Zconj, 'eye', ephasing)*(conn.B - conn.I)*kdiag(Yconj, dalpha, ephasing) + ...
%             kdiag('eye', {branch.Z}, ephasing)*(conn.B - conn.I)*kdiag('eye',cellfun(@(x,y) x*y, ensure_col_vect(Y), dalpha, 'UniformOutput', false), ephasing) +...
%             kdiag('eye', dalpha, ephasing);
%         end
        Beta  = conn.I - Gamma;
    otherwise
        error('distflow_multi: alpha method %d is not implemented', opt.alpha_method)
end


if opt.mats_gen
	if (opt.alpha_method ~=1) && (opt.alpha_method ~=12)
		warning(['distflow_multi: option opt.mats_gen=1 is intended to be used only with',...
		         'opt.alpha_method=1 or opt.alpha_method=12, but input is opt.alpha_method=%d.'], opt.alpha_method)
	end
	varargout{1} = Beta;
	varargout{2} = K;
	varargout{3} = zeta;
	varargout{4} = eta;
	varargout{5} = v0;
	varargout{6} = conn;
	return
end
%% solve

if opt.calcmu
    if ~exist('bustmp','var')
        bustmp = distflow_multi(bus,branch,opt.bustmpopt);
    end
    mu = getmu(bustmp, branch);
    nu = (Gamma*conn.M + 2*(Gamma+conn.I) + K)\(Gamma*conn.M*v0 - zeta*sigma - eta*conj(sigma) + (Gamma + conn.I)*mu);
else
    nu = (Beta*conn.M - K)\(Beta*conn.M*v0 + zeta*sigma + eta*conj(sigma));
end


if opt.alpha_method > 1
  xi  = (kdiag(Yconj, ydalpha, ephasing) - kdiag(ycalpha, Y, ephasing))*conn.M*(nu - v0);
else
  xi  = sparse(conn.E,1);
end
psi = conn.B*(conn.TE*kdiag('eye','gamma', nphasing(2:end))*sigma +...
  kdiag(yl, 'eye', nphasing(2:end))*nu + kdiag('eye',{branch.Z},ephasing)*xi);


start_time = tic;
for i = 1: opt.number_iteration
    v2 = conn.U*nu;
    if (max(abs(imag(v2))) > 1e-8) && ~opt.suppress_warnings
        warning(['distflow_multi: imaginary entries in v^2 with magnitude larger than 1e-8 found.\n\t',...
                 'Max imaginary magnitude is %0.4g.\n\t These are discarded in the result'], max(abs(imag(v2))))
    end
    v = sqrt(real(v2));
    branch_flow = conn.U*psi;
end
end_time = toc(start_time);

varargout{1}   = updatebus(bus,v);
varargout{2}   = updatebranch(branch, branch_flow );
varargout{3}   = end_time;
%% Utility functions
function S = connmats(bus, branch)
%%% f and t are vectors with bus indices, nphasing is a cell array with the
%%% phase vectors for **all the nodes** 

idx  = reshape(1:9,3,3);
ephasing = {branch.phase}.';
nphasing = {bus.phase}.';
f = [branch.f].';
t = [branch.t].';

% node mapping returning global index
ridx = cell2mat(cellfun(@(x,y) y*ones(length(x)^2,1), nphasing, num2cell(1:length(nphasing)).','UniformOutput',false));
cidx = cell2mat(cellfun(@(x,y) vec(idx(x,x)), nphasing, 'UniformOutput',false));
S.nidx = sparse(ridx,cidx,1:length(cidx),length(nphasing), numel(idx));

% edge mapping returning global index
ridx = cell2mat(cellfun(@(x,y) y*ones(length(x)^2,1), ephasing, num2cell(1:length(ephasing)).','UniformOutput',false));
cidx = cell2mat(cellfun(@(x,y) vec(idx(x,x)), ephasing, 'UniformOutput',false));
S.eidx = sparse(ridx, cidx, 1:length(cidx), length(ephasing), numel(idx));

S.E = max(S.eidx(end,:));
S.N = max(S.nidx(end,:));

cidx = cell2mat(cellfun(@(x,y) full(S.nidx(y,vec(idx(x,x)))).', nphasing(t), num2cell(f), 'UniformOutput', false));
S.F  = sparse(1:S.E, cidx,1, S.E, S.N);

cidx = cell2mat(cellfun(@(x,y) full(S.nidx(y,vec(idx(x,x)))).', nphasing(t), num2cell(t), 'UniformOutput', false));
S.T  = sparse(1:S.E, cidx, 1, S.E, S.N);

tmp  = min(S.nidx(2,:));
S.M  = S.F(:,tmp:end) - S.T(:,tmp:end);
S.TE = S.T(:,tmp:end);

S.I = sparse(1:S.E,1:S.E,1);

S.B = inv(S.I - S.T*S.F');

S.U = unvecd(nphasing(2:end));

% function [yl, ylc] = yload(bus)
% D = [1 -1 0; 0 1 -1; -1 0 1];
% ydflag = isfield(bus,'yd');
% yshflag = isfield(bus,'Ysh');
% yyflag  = isfield(bus,'yy');
% yl = cell(length(bus)-1, 1);
% for k = 2:length(bus)
%     %%% delta portion
%     if ~ydflag
%         yd = 0;
%     elseif (length(bus(k).phase) < 2)
%         if any(bus(k).yd ~= 0)
%             warning('distflow_multi: Ignoring delta load on single phase bus.')
%         end
%         yd = 0;
%     else
%         yd = D(:,bus(k).phase)'*diag(conj(bus(k).yd))*D(:,bus(k).phase);
%     end
%     %%% shunt portion
%     if ~yshflag
%         ysh = 0;
%     else
%         ysh = bus(k).Ysh';
%     end
%     %% constant impedance laod
%     if ~yyflag
%         yy = 0;
%     else
%         yy = diag(bus(k).yy)';
%     end
%     yl{k-1} = (ysh + yy + yd).'; %note only transpose, NOT hermitian.
% end
% ylc = cellfun(@conj, yl, 'UniformOutput', false);

% function sigma = getsigma(bus)
% 
% D = [1 -1 0; 0 1 -1; -1 0 1];
% % D = eye(3);
% % A = 0.5*[1 -1 1; 1 1 -1; -1 1 1];
% % B = [0 1 1; 1 0 1; 1 1 0];
% % tmp = exp(1i*pi/6);
% % B2 = [conj(tmp) 0 tmp; tmp conj(tmp) 0; 0 tmp conj(tmp)]; 
% idx  = {1, [1,4].', [1,5,9].'};
% sdflag = isfield(bus, 'sd');
% ridx = cell(length(bus)-1,1);
% vidx = cell(length(bus)-1,1);
% ptr = 0;
% for k = 2:length(bus)
%     if sdflag && ~all(bus(k).sd == 0)
%         tmpsd = ensure_col_vect(bus(k).sd);
% %         switch sum(tmpsd ~=0 )
% %             case  3
% %                 ztmp  = 1./conj(tmpsd);
% %                 tmp   = ztmp./(A*(ztmp.*(B*ztmp))/sum(ztmp));
% %             otherwise
% %                 tmp = 3;
% %         end
% %         sd = diag(tmp)*D(:,bus(k).phase).'*tmpsd
%         sd = sqrt(3)*diag(D(:,bus(k).phase).'*diag(tmpsd)*D(:,bus(k).phase));
% %         sd = diag(gamma_phi(bus(k).phase)*D(:,bus(k).phase).'*diag(tmpsd)*D(:,bus(k).phase));
%     else
%         sd = 0;
%     end
%         
%     if any(bus(k).sy ~= 0) || any(sd~=0)
%         vidx{k} = ensure_col_vect(bus(k).sy) + sd;
%         ridx{k} = ptr + idx{length(bus(k).phase)};
%         if length(vidx{k}) ~= length(ridx{k})
%             error('distflow_multi: inconsistent sizes on bus %d between phase (%d x 1) and sy (%d x 1)', ...
%                 k, length(bus(k).phase), length(bus(k).sy))
%         end
%     end
%     ptr = ptr + length(bus(k).phase)^2;
% end
% sigma = sparse(cell2mat(ridx), 1, cell2mat(vidx), ptr, 1);

% function g = gamma_phi(phases)
% a = exp(-1i*2*pi/3);
% gamma = [1  , a^2, a  ;
%          a  , 1  , a^2;
%          a^2, a  , 1];
% g = gamma(phases,phases);

% function [g, gc] = branchgamma(conn, sigma, Zconj, ephasing)
% 
% S = conn.B*conn.TE*sigma;
% Zc= conn.B*conn.TE*cell2mat(cellfun(@vec, Zconj.', 'UniformOutput', false));
% % v = conn.U*spfun(@(x) 1./x, sqrt(abs(S.*Zc)));
% v = conn.U*spfun(@(x) 1./x, sqrt(abs(S)));
% v(v==0) = 1;
% v = vect2cell(v, ephasing, 0);
% g = cellfun(@(x,y) ((1./x)*x.').*gamma_phi(y), v, ephasing, 'UniformOutput', false);
% gc = cellfun(@(x) conj(x), g, 'UniformOutput', false);
function [g, gc] = branchgamma(bustmp, branch)

v = cellfun(@(x,y) full(sparse( double(x), 1, y, 3, 1)), {bustmp([branch.f]).phase}, {bustmp([branch.f]).vm}, 'UniformOutput', false);
g = cellfun(@(x,y) ((1./x(y))*x(y).').*gamma_phi(y), v, {branch.phase}, 'UniformOutput', false);
gc = cellfun(@(x) conj(x), g, 'UniformOutput', false);

function mu = getmu(bustmp, branch)

v = cellfun(@(x,y) full(sparse( double(x), 1, y, 3, 1)), {bustmp.phase}, {bustmp.vm}, 'UniformOutput', false);
m = cellfun(@(f,t,phi) diag(v{f}(phi))*gamma_phi(phi)*diag(v{t}(phi)) + diag(v{t}(phi))*gamma_phi(phi)*diag(v{f}(phi)),...
    {branch.f}, {branch.t}, {branch.phase}, 'UniformOutput', false);
mu = cell2mat(cellfun(@vec, m, 'UniformOutput', false).');

function [v0, I0] = v0vec(vref, ephasing)
%%% phasing is a n-1 x 1 cell array where each entry contains a vector with 
%%% the phasing of the given branch. For example, if branch 7 (that one whose
%%% `to` node is 8) has phases A and B then: `phasing{7} = [1,2]`

pnum = sqrt(length(vref));
idx  = reshape(1:length(vref), pnum, pnum);
cidx = cell2mat(cellfun(@(y) vec(idx(y,y)), ephasing, 'UniformOutput', false));
I0   = sparse(1:length(cidx), cidx, 1, length(cidx), numel(idx));
v0   = I0*vref;
% Iphi0 = speye(length(vref));
% x = cell2mat(cellfun(@(y) Iphi0(vec(idx(y,y)),:), phasing))*vref;

% function A = kdiag(x,y, phases)
% %%% x and y should be cells with matrix entries, 'eye', or 'gamma', 'gamma_conj'
% 
% n  = length(phases);
% ridx = cell(n,1);
% cidx = cell(n,1);
% vidx = cell(n,1);
% ptr  = 0;
% for k = 1:n
%     try
%         xtmp = kdiag_tmpmat(x{k}, phases{k});
%     catch ME
%         if strcmp(ME.identifier, 'MATLAB:cellRefFromNonCell')
%             xtmp = kdiag_tmpmat(x, phases{k});
%         else
%             rethrow(ME)
%         end
%     end
%     try
%         ytmp = kdiag_tmpmat(y{k}, phases{k});
%     catch ME
%         if strcmp(ME.identifier, 'MATLAB:cellRefFromNonCell')
%             ytmp = kdiag_tmpmat(y, phases{k});
%         else
%             rethrow(ME)
%         end
%     end
%     [rtmp,ctmp,vtmp] = find(kron(xtmp, ytmp));
% 	ridx{k} = ptr + rtmp;
% 	cidx{k} = ptr + ctmp;
% 	vidx{k} = vtmp;
% 
% 	ptr = ptr + length(phases{k})^2;
% end
% A = sparse(cell2mat(ridx), cell2mat(cidx), cell2mat(vidx), ptr, ptr);
% 
% function xtmp = kdiag_tmpmat(x, phi)
% if strcmp(x, 'eye')
%     xtmp = eye(length(phi));
% elseif strcmp(x, 'gamma')
%     xtmp = gamma_phi(phi);
% elseif strcmp(x, 'gammac')
%     xtmp = conj(gamma_phi(phi));
% else
%     xtmp = x;
% end

function U = unvecd(phasing)
%%% for each block select the diagonal entries of the reshaped square
%%% matrix

n    = sum(cellfun(@length, phasing)); % number of phase variables
ridx = (1:n).';
cidx = cell(length(phasing),1);
idx  = {1, [1,4].', [1,5,9].'};
ptr = 0;
for k = 1:length(phasing)
    cidx{k} = ptr + idx{length(phasing{k})};
    ptr = ptr + length(phasing{k})^2;
end
U = sparse(ridx, cell2mat(cidx),1, n, ptr);

function C = vect2cell(x, phasing, sq)
%%% take vector x and split it up into a cell of size(phasing).
%%% sq says wether to step the pointer linearly (false, default) or squaring the
%%% length of the phase vectors (true)
if nargin < 3
    sq = false;
end
C = cell(length(phasing),1);
ptr1 = 0;
for k = 1:length(phasing)
    if ~sq
        ptr2 = ptr1 + length(phasing{k});
    else
        ptr2 = ptr1 + length(phasing{k})^2;
    end
    C{k} = x(ptr1+1:ptr2);
    ptr1 = ptr2;
end

function bus = updatebus(bus,v)
bus(1).vm = bus(1).vref*ones(length(bus(1).phase),1);
ptr = 0;
for k = 2:length(bus)
    bus(k).vm = v(ptr + (1:length(bus(k).phase)));
    ptr = ptr + length(bus(k).phase);
end

function branch = updatebranch(branch, S)
ptr = 0;
for k = 1:length(branch)
  branch(k).S = S(ptr + (1:length(branch(k).phase)));
  ptr = ptr + length(branch(k).phase);
end

function opt = optdefaults(opt)
optd = struct('alpha', 0.5, 'alpha_method', 1, 'mats_gen', 0, 'gamma_method', 1, 'calcmu', 0, 'bustmpopt', [], 'suppress_warnings', 0, 'number_iteration' , 1);
if isempty(opt)
    opt = optd;
else
    opt = struct_compare(optd, opt);
end

function b = struct_compare(a, b)
% compares structure b to structure a.
% if b lacks a field in a it is added
% this is performed recursively, so if if a.x is a structure
% and b has field x, the the function is called on (a.x, b.x)
for f = fieldnames(a).'
	if ~isfield(b, f{:})
		b.(f{:}) = a.(f{:});
	elseif isstruct(a.(f{:}))
		b.(f{:}) = struct_compare(a.(f{:}), b.(f{:}));
	end
end
