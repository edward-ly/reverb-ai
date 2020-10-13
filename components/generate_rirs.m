function [irLeft, irRight] = generate_rirs(plugin, sampleRate)
% GENERATE_RIRS Generate new impulse responses for stereo plugin
%
% Input arguments:
% plugin = plugin object containing IR properties
% sampleRate = sample rate of plugin
%
% Output arguments:
% irLeft = impulse response assigned to left audio channel
% irRight = impulse response assigned to right audio channel
%
  % Require all arguments
  if nargin < 2, error('Not enough input arguments.'); end
  if nargout < 2, error('Not enough output arguments.'); end

  % =========================================================================

  % Pre-process parameter values
  % Convert EDT to seconds
  pEDT = plugin.EDT * plugin.T60 / 100.0;

  % Get GA parameters
  if plugin.QUALITY == Quality.Max
    gaParams = plugin.GA_PARAMS.Max;
  elseif plugin.QUALITY == Quality.High
    gaParams = plugin.GA_PARAMS.High;
  elseif plugin.QUALITY == Quality.Medium
    gaParams = plugin.GA_PARAMS.Medium;
  else % plugin.QUALITY == Quality.Low
    gaParams = plugin.GA_PARAMS.Low;
  end

  % Calculate number of predelay samples
  delayLeft = round(plugin.L_DELAY * sampleRate / 1000);
  delayRight = round(plugin.R_DELAY * sampleRate / 1000);

  % Struct for IR parameters
  irParamsLeft = struct( ...
    'SAMPLE_RATE', plugin.IR_SAMPLE_RATE, ...
    'NUM_SAMPLES', plugin.IR_NUM_SAMPLES, ...
    'PREDELAY', delayLeft, ...
    'T60', plugin.T60, ...
    'EDT', pEDT, ...
    'C80', plugin.C80, ...
    'BR', plugin.WARMTH);

  if plugin.STEREO
    % Additional struct for IR parameters (right channel)
    irParamsRight = struct( ...
      'SAMPLE_RATE', plugin.IR_SAMPLE_RATE, ...
      'NUM_SAMPLES', plugin.IR_NUM_SAMPLES, ...
      'PREDELAY', delayRight, ...
      'T60', plugin.T60, ...
      'EDT', pEDT, ...
      'C80', plugin.C80, ...
      'BR', plugin.WARMTH);

    % Generate new impulse responses
    newIRs = zeros(irParamsLeft.NUM_SAMPLES, 2);
    newIRs(:, 1) = genetic_rir(gaParams, irParamsLeft);
    newIRs(:, 2) = genetic_rir(gaParams, irParamsRight);

    if plugin.NORMALIZE_STEREO
      % Modify gains of IRs so that RMS levels are equal
      [newIRs(:, 1), newIRs(:, 2)] = normalize_rms(newIRs(:, 1), newIRs(:, 2));
    else
      % Modify gains of IRs so that RMS difference is no more than maximum
      % ILD (interaural level difference)
      [newIRs(:, 1), newIRs(:, 2)] = limit_ild(newIRs(:, 1), newIRs(:, 2));
    end

    % Normalize to prevent clipping
    newIRs = normalize_signal(newIRs, 0.99);

    % Resample/resize impulse responses, assign to output
    irLeft = resample_ir(plugin, newIRs(:, 1), sampleRate)';
    irRight = resample_ir(plugin, newIRs(:, 2), sampleRate)';
  else
    % Generate new impulse response
    newIR = genetic_rir(gaParams, irParamsLeft);

    % Normalize to prevent clipping
    newIR = normalize_signal(newIR, 0.99);

    % Resample/resize impulse response
    ir = resample_ir(plugin, newIR, sampleRate)';

    % Assign IR to both channels
    irLeft = ir; irRight = ir;
  end

  % Apply predelay
  irLeft = [zeros(1, delayLeft), irLeft(1:(end - delayLeft))];
  irRight = [zeros(1, delayRight), irRight(1:(end - delayRight))];
end
