% Class file for a VST 2 plugin that performs IR-based reverb in real-time
% via frequency-domain partitioned convolution, while adding the ability to
% shape the impulse response using a genetic algorithm, as well as control the
% dry/wet mix and gain of the output signal.
%
% File: GeneticReverb.m
% Author: Edward Ly (m5222120@u-aizu.ac.jp)
% Version: 2.0.2
% Last Updated: 12 November 2019
%
% Usage: Validate and generate the VST plugin, respectively, with:
%     validateAudioPlugin GeneticReverb
%     generateAudioPlugin GeneticReverb
% then copy the generated plugin file to the plugin path of your DAW.
% If you want to save impulse responses generated by the plugin, also make sure
% that you have write access to the plugin path directory.
%
% BSD 3-Clause License
% 
% Copyright (c) 2019, Edward Ly
% All rights reserved.
% 
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are met:
% 
% 1. Redistributions of source code must retain the above copyright notice, this
%    list of conditions and the following disclaimer.
% 
% 2. Redistributions in binary form must reproduce the above copyright notice,
%    this list of conditions and the following disclaimer in the documentation
%    and/or other materials provided with the distribution.
% 
% 3. Neither the name of the copyright holder nor the names of its
%    contributors may be used to endorse or promote products derived from
%    this software without specific prior written permission.
% 
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
% FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
% DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
% SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
% OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

classdef (StrictDefaults) GeneticReverb < audioPlugin & matlab.System
    properties
        % Public variables
        T60 = 1;                  % Total reverberation time (s)
        EDT = 0.1;                % Early decay time (T10) (s)
        ITDG = 0;                 % Initial time delay gap (s)
        C80 = 0;                  % Clarity (dB)
        WARMTH = 50;              % Warmth Amount (%)
        QUALITY = Quality.low;    % Reverb quality
        STEREO = true;            % Enable stereo effect
        MIX = 50;                 % Dry/Wet Mix (%)
        GAIN = 0;                 % Gain of output signal (dB)
        SAVE_IR = true;           % Toggle to save IR to file
    end

    properties (Constant)
        % Interface parameters
        PluginInterface = audioPluginInterface( ...
            'InputChannels', 2, ...
            'OutputChannels', 2, ...
            'PluginName', 'Genetic Reverb', ...
            audioPluginParameter('T60', ...
                'DisplayName', 'Decay Time', ...
                'Label', 's', ...
                'Mapping', {'log', 0.1, 10}), ...
            audioPluginParameter('EDT', ...
                'DisplayName', 'Early Decay Time', ...
                'Label', 's', ...
                'Mapping', {'log', 0.01, 1}), ...
            audioPluginParameter('ITDG', ...
                'DisplayName', 'Intimacy', ...
                'Label', 's', ...
                'Mapping', {'lin', 0, 0.5}), ...
            audioPluginParameter('C80', ...
                'DisplayName', 'Clarity', ...
                'Label', 'dB', ...
                'Mapping', {'lin', -5, 5}), ...
            audioPluginParameter('WARMTH', ...
                'DisplayName', 'Warmth', ...
                'Label', '%', ...
                'Mapping', {'lin', 0, 100}), ...
            audioPluginParameter('QUALITY', ...
                'DisplayName', 'Quality', ...
                'Mapping', {'enum', 'Low', 'Medium', 'High'}), ...
            audioPluginParameter('STEREO', ...
                'DisplayName', 'Mono/Stereo', ...
                'Mapping', {'enum', 'Mono', 'Stereo'}), ...
            audioPluginParameter('MIX', ...
                'DisplayName', 'Dry/Wet', ...
                'Label', '%', ...
                'Mapping', {'lin', 0, 100}), ...
            audioPluginParameter('GAIN', ...
                'DisplayName', 'Output Gain', ...
                'Label', 'dB', ...
                'Mapping', {'pow', 1/3, -60, 6}), ...
            audioPluginParameter('SAVE_IR', ...
                'DisplayName', 'Toggle To Save', ...
                'Mapping', {'enum', 'Switch Right', 'Switch Left'}))
    end

    properties (Nontunable)
        % Constant parameters
        IR_SAMPLE_RATE = 16000;   % Sample rate of generated IRs
        PARTITION_SIZE = 1024;    % Default partition length of conv filters
    end

    properties
        % System objects for partitioned convolution of audio stream with
        % impulse response (identified by numerator length)
        pFIRFilterLeft22500;   pFIRFilterRight22500;
        pFIRFilterLeft45000;   pFIRFilterRight45000;
        pFIRFilterLeft90000;   pFIRFilterRight90000;
        pFIRFilterLeft180000;  pFIRFilterRight180000;
        pFIRFilterLeft360000;  pFIRFilterRight360000;
        pFIRFilterLeft720000;  pFIRFilterRight720000;
        pFIRFilterLeft1440000; pFIRFilterRight1440000;
        pFIRFilterLeft2880000; pFIRFilterRight2880000;

        % Track number of required samples in impulse response
        % (before and after resampling)
        IR_NUM_SAMPLES = 12000;
        NUM_SAMPLES = 45000;

        % System objects for resampling IR to audio sample rate
        pFIR22050     % 16 kHz to 22.05 kHz
        pFIR32000     % 16 kHz to 32 kHz
        pFIR44100     % 16 kHz to 44.1 kHz
        pFIR48000     % 16 kHz to 48 kHz
        pFIR88200     % 16 kHz to 88.2 kHz
        pFIR96000     % 16 kHz to 96 kHz
        pFIR192000    % 16 kHz to 192 kHz
    end

    % Plugin methods for frequency-domain partitioned convolution
    methods (Access = protected)
        % Main process function
        function out = stepImpl (plugin, in)
            % Calculate next convolution step for both channels
            if plugin.NUM_SAMPLES == 22500
                outL = step(plugin.pFIRFilterLeft22500, in(:, 1));
                outR = step(plugin.pFIRFilterRight22500, in(:, 2));
            elseif plugin.NUM_SAMPLES == 45000
                outL = step(plugin.pFIRFilterLeft45000, in(:, 1));
                outR = step(plugin.pFIRFilterRight45000, in(:, 2));
            elseif plugin.NUM_SAMPLES == 90000
                outL = step(plugin.pFIRFilterLeft90000, in(:, 1));
                outR = step(plugin.pFIRFilterRight90000, in(:, 2));
            elseif plugin.NUM_SAMPLES == 180000
                outL = step(plugin.pFIRFilterLeft180000, in(:, 1));
                outR = step(plugin.pFIRFilterRight180000, in(:, 2));
            elseif plugin.NUM_SAMPLES == 360000
                outL = step(plugin.pFIRFilterLeft360000, in(:, 1));
                outR = step(plugin.pFIRFilterRight360000, in(:, 2));
            elseif plugin.NUM_SAMPLES == 720000
                outL = step(plugin.pFIRFilterLeft720000, in(:, 1));
                outR = step(plugin.pFIRFilterRight720000, in(:, 2));
            elseif plugin.NUM_SAMPLES == 1440000
                outL = step(plugin.pFIRFilterLeft1440000, in(:, 1));
                outR = step(plugin.pFIRFilterRight1440000, in(:, 2));
            elseif plugin.NUM_SAMPLES == 2880000
                outL = step(plugin.pFIRFilterLeft2880000, in(:, 1));
                outR = step(plugin.pFIRFilterRight2880000, in(:, 2));
            else
                outL = in(:, 1);
                outR = in(:, 2);
            end
            out = [outL outR];

            % Apply dry/wet mix
            out = in .* (1 - plugin.MIX / 100) + out .* plugin.MIX ./ 100;

            % Apply output gain
            gain = 10 ^ (plugin.GAIN / 20);
            out = out .* gain;
        end

        % DSP initialization / setup
        function setupImpl (plugin, ~)
            % Initialize resampler objects:
            % 22.05/44.1/88.2 kHz sample rates are rounded to 22/44/88 kHz for
            % simplicity
            plugin.pFIR22050 = dsp.FIRRateConverter(11, 8);
            plugin.pFIR32000 = dsp.FIRInterpolator(2);
            plugin.pFIR44100 = dsp.FIRRateConverter(11, 4);
            plugin.pFIR48000 = dsp.FIRInterpolator(3);
            plugin.pFIR88200 = dsp.FIRRateConverter(11, 2);
            plugin.pFIR96000 = dsp.FIRInterpolator(6);
            plugin.pFIR192000 = dsp.FIRInterpolator(12);

            % Initialize convolution filters
            plugin.pFIRFilterLeft22500 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(22500), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterLeft45000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(45000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterLeft90000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(90000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterLeft180000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(180000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterLeft360000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(360000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterLeft720000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(720000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterLeft1440000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(1440000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterLeft2880000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(2880000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);

            plugin.pFIRFilterRight22500 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(22500), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterRight45000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(45000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterRight90000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(90000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterRight180000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(180000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterRight360000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(360000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterRight720000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(720000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterRight1440000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(1440000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
            plugin.pFIRFilterRight2880000 = dsp.FrequencyDomainFIRFilter( ...
                'Numerator', init_ir(2880000), ...
                'PartitionForReducedLatency', true, ...
                'PartitionLength', plugin.PARTITION_SIZE);
        end

        % Initialize/reset system object properties
        function resetImpl (plugin)
            reset(plugin.pFIRFilterLeft22500);
            reset(plugin.pFIRFilterLeft45000);
            reset(plugin.pFIRFilterLeft90000);
            reset(plugin.pFIRFilterLeft180000);
            reset(plugin.pFIRFilterLeft360000);
            reset(plugin.pFIRFilterLeft720000);
            reset(plugin.pFIRFilterLeft1440000);
            reset(plugin.pFIRFilterLeft2880000);

            reset(plugin.pFIRFilterRight22500);
            reset(plugin.pFIRFilterRight45000);
            reset(plugin.pFIRFilterRight90000);
            reset(plugin.pFIRFilterRight180000);
            reset(plugin.pFIRFilterRight360000);
            reset(plugin.pFIRFilterRight720000);
            reset(plugin.pFIRFilterRight1440000);
            reset(plugin.pFIRFilterRight2880000);

            reset(plugin.pFIR22050);
            reset(plugin.pFIR32000);
            reset(plugin.pFIR44100);
            reset(plugin.pFIR48000);
            reset(plugin.pFIR88200);
            reset(plugin.pFIR96000);
            reset(plugin.pFIR192000);
        end

        % Do something when certain parameters are changed
        function processTunedPropertiesImpl (plugin)
            % Detect change in "toggle to save" parameter
            propChangeSave = isChangedProperty(plugin, 'SAVE_IR');

            % Detect changes in reverb parameters
            propChangeIR = isChangedProperty(plugin, 'T60') || ...
                isChangedProperty(plugin, 'ITDG') || ...
                isChangedProperty(plugin, 'EDT') || ...
                isChangedProperty(plugin, 'C80') || ...
                isChangedProperty(plugin, 'WARMTH') || ...
                isChangedProperty(plugin, 'QUALITY') || ...
                isChangedProperty(plugin, 'STEREO');

            % Get current sample rate of plugin
            sampleRate = getSampleRate(plugin);

            % Save current impulse responses to file
            if propChangeSave, save_irs(plugin, sampleRate); end

            % Generate new impulse responses
            if propChangeIR
                % Calculate number of samples needed for impulse response
                % (before and after resampling)
                plugin.IR_NUM_SAMPLES = ceil( ...
                    1.5 * plugin.T60 * plugin.IR_SAMPLE_RATE);
                plugin.NUM_SAMPLES = ceil( ...
                    plugin.IR_NUM_SAMPLES * sampleRate / plugin.IR_SAMPLE_RATE);

                % Determine filter with smallest possible buffer length
                filterIndex = ceil(log2(plugin.NUM_SAMPLES / 22500));
                if filterIndex < 0, filterIndex = 0; end

                % Extend NUM_SAMPLES to length of an entire buffer
                plugin.NUM_SAMPLES = 22500 * 2 ^ filterIndex;

                % Generate new impulse responses
                [irLeft, irRight] = generate_rirs(plugin, sampleRate);

                % Assign new IRs to appropriate filters
                if plugin.NUM_SAMPLES == 22500
                    plugin.pFIRFilterLeft22500.Numerator = irLeft(1:22500);
                    plugin.pFIRFilterRight22500.Numerator = irRight(1:22500);
                elseif plugin.NUM_SAMPLES == 45000
                    plugin.pFIRFilterLeft45000.Numerator = irLeft(1:45000);
                    plugin.pFIRFilterRight45000.Numerator = irRight(1:45000);
                elseif plugin.NUM_SAMPLES == 90000
                    plugin.pFIRFilterLeft90000.Numerator = irLeft(1:90000);
                    plugin.pFIRFilterRight90000.Numerator = irRight(1:90000);
                elseif plugin.NUM_SAMPLES == 180000
                    plugin.pFIRFilterLeft180000.Numerator = irLeft(1:180000);
                    plugin.pFIRFilterRight180000.Numerator = irRight(1:180000);
                elseif plugin.NUM_SAMPLES == 360000
                    plugin.pFIRFilterLeft360000.Numerator = irLeft(1:360000);
                    plugin.pFIRFilterRight360000.Numerator = irRight(1:360000);
                elseif plugin.NUM_SAMPLES == 720000
                    plugin.pFIRFilterLeft720000.Numerator = irLeft(1:720000);
                    plugin.pFIRFilterRight720000.Numerator = irRight(1:720000);
                elseif plugin.NUM_SAMPLES == 1440000
                    plugin.pFIRFilterLeft1440000.Numerator = irLeft(1:1440000);
                    plugin.pFIRFilterRight1440000.Numerator = ...
                        irRight(1:1440000);
                elseif plugin.NUM_SAMPLES == 2880000
                    plugin.pFIRFilterLeft2880000.Numerator = irLeft(1:2880000);
                    plugin.pFIRFilterRight2880000.Numerator = ...
                        irRight(1:2880000);
                end
            end
        end
    end
end
