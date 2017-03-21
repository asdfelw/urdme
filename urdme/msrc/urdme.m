function umod = urdme(umod,varargin)
%URDME Interface to spatial stochastic simulation algorithms.
%   UMOD = URDME(UMOD,...) generates a single trajectory for the
%   diffusion/transport model defined in the URDME-struct UMOD. The
%   arguments to URDME are passed via property/value pairs, see the
%   table below.
%
%   For example,
%     UMOD = URDME(UMOD,'solver','mysolver','propensities','mymodel')
%   compiles the solver 'mysolver', assumed to have the Mex-interface
%   source file 'mexmysolver.c', together with the propensity source
%   file 'mymodel.c' for the reactions.
%
%   Comsol Java objects are conventionally stored in UMOD.comsol and
%   PDE Toolbox structures in UMOD.pde. After simulating the resulting
%   object may be loaded back into Comsol (or PDE Toolbox) for
%   visualization and postprocessing. See URDME2COMSOL and URDME2PDE.
%
%   Property        Value/{Default}         Description
%   -----------------------------------------------------------------------
%   solver          string {'nsm'}          Name of solver
%   propensities    string                  Name of propensity .c-file
%   report          {0}, 1, 2, 3            Level of report
%   compile         {1} | 0                 Compile on/off
%   parse           {1} | 0                 Parse on/off
%   seed            double {NaN}            Solver random number seed
%
%   The URDME Matlab interface supports three levels of report: 0
%   (silent), 1 (intermediate), 2 (comprehensive), 3 (as 2, but also
%   allowing for an early exit).
%
%   Turn compilation off when you are solving the same model several
%   times and after the first call to URDME. You may similarly turn
%   parsing off after the UMOD-struct has been extended correctly once
%   (and preferably checked). For example,
%     % first call, compile mymodel.c:
%     UMOD = URDME(UMOD,'propensities','mymodel','seed',1234);
%     % second call, new seed, no compilation:
%     UMOD = URDME(UMOD,'seed',2345,'compile',0);
%     % a sequence of calls:
%     UMOD.parse = 0; % don't parse the URDME struct
%     for seed = 1:10
%       UMOD.seed = seed; % set seed directly
%       UMOD = URDME(UMOD);
%     end
%
%   The URDME solver sequence takes the generic form
%     make_<UMOD.solver>(UMOD.propensities);
%     UMOD.U = mex<UMOD.solver>(UMOD.tspan,UMOD.u0, ...
%                UMOD.D,UMOD.N,UMOD.G, ...
%                UMOD.vol,UMOD.ldata,UMOD.gdata,UMOD.sd, ...
%                UMOD.report,UMOD.seed,UMOD.solverargs);
%
%   See also COMSOL2URDME, URDME2COMSOL, URDME_VALIDATE, NSM.

%   The URDME-struct has the following fields:
%   -----------------------------------------------------------------------
%
%   Required fields before call:
%
%   tspan           Time vector
%   u0              Initial state
%   D               Diffusion matrix
%   N               Stoichiometric matrix
%   G               Dependency graph
%   vol             Voxel volumes
%   sd              Subdomain numbers
%
%   Usually passed as options to URDME:
%
%   solver          Solver
%   propensities    Propensity source file
%   report          Solver feedback
%   compile         Compilation on/off
%   parse           Parsing on/off
%   seed            Random seed
%
%   Optional, empty understood when left out:
%
%   ldata           Local data vector
%   gdata           Global data vector
%   solverargs      Arguments to solver, property/value cell-vector
%
%   Optional:
%
%   U               Latest stored solution
%   comsol          Comsol Java object
%   pde             PDE Toolbox structure
%   private         Field to store anything extra

% S. Engblom 2017-02-15 (Major revision, URDME 1.3, Comsol 5)
% P. Bauer, S. Engblom 2012-04-04 (Revision, cleanup)
% V. Gerdin 2012-02-01 (Revision, Comsol 4.2)
% B. Drawert, A. Hellander 2010-06-07 (Revision, background mode)
% J. Cullhed 2008-06-18

% parse property/value pairs, the logic of this if-statement is: (1)
% either options have been given, or (2) the umod-struct is
% incomplete, or (3) the umod-struct instructs us to parse it
if nargin > 1 || ~isfield(umod,'parse') || umod.parse
  % default options
  optdef = struct('solver','nsm', ...
                  'propensities','', ...
                  'report',0, ...
                  'compile',1, ...
                  'parse',1, ...
                  'seed',NaN, ...
                  'tspan',[], ...
                  'u0',[], ...
                  'D',[], ...
                  'N',[], ...
                  'G',[], ...
                  'vol',[], ...
                  'sd',[], ...
                  'ldata',[], ...
                  'gdata',[], ...
                  'solverargs',{{}}, ...
                  'U',[], ...
                  'comsol',[], ...
                  'pde',[], ...
                  'private',[]);
  % input options
  try
    opts = struct(varargin{:});
  catch
    error('Could not create Matlab struct from input property/value pairs.');
  end

  % merge options: opts --> umod, opts takes precedence
  fn = fieldnames(opts);
  for i = 1:length(fn)
    umod = setfield(umod,fn{i},getfield(opts,fn{i}));
  end

  % merge options: umod --> optdef, umod takes precedence
  fn = fieldnames(umod);
  for i = 1:length(fn)
    if ~isfield(optdef,fn{i})
      error(sprintf('Unrecognized property ''%s''.',fn{i}));
    end
    optdef = setfield(optdef,fn{i},getfield(umod,fn{i}));
  end
  umod = optdef;
end

% possibly add empty fields and then check the URDME struct
if umod.parse
  if isempty(umod.ldata)
    umod.ldata = zeros(0,numel(umod.vol));
  end
  urdme_validate(umod);
else
  l_info(umod.report,2,'Parsing turned off.\n');
end

% (1) Compile the solver.
if umod.compile
  % propensities, if any
  if ~isempty(umod.propensities) && ~any(umod.propensities == '.')
    umod.propensities = [umod.propensities '.c'];
  end
  feval(['mexmake_' umod.solver],umod.propensities);
else
  l_info(umod.report,2,'Compilation turned off.\n');
end

% (2) Solve!
if umod.report >= 2, solver_timer = tic; end 
l_info(umod.report,1,'Starting simulation...\n');
umod.U = feval(['mex' umod.solver], ...
               umod.tspan,umod.u0,umod.D,umod.N,umod.G, ...
               umod.vol,umod.ldata,umod.gdata,umod.sd, ...
               umod.report,umod.seed, ...
               umod.solverargs);
l_info(umod.report,1,'   ...done.\n');
if umod.report >= 2
  fprintf('Solver execution time = %gs.\n',toc(solver_timer));
end

%-------------------------------------------------------------------------
function l_info(level,lim,msg)
%L_INFO Display information.
%   L_INFO(LEVEL,LIM,MSG) Displays the message MSG whenever LEVEL >=
%   LIM.

if level >= lim, fprintf(msg); end

%-------------------------------------------------------------------------