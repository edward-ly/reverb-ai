% Class file for a VST 2 plugin that performs IR-based reverb in real-time
% via frequency-domain partitioned convolution, while adding the ability to
% shape the impulse response using a genetic algorithm, as well as control the
% dry/wet mix and gain of the output signal.
%
% File: GeneticReverb.m
% Author: Edward Ly (m5222120@u-aizu.ac.jp)
% Version: 3.1.2
% Last Updated: 18 January 2020
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
        WARMTH = 50;              % Warmth Amount (%)
        ITDG = 10;                % Initial time delay gap (ms)
        C80 = 0;                  % Clarity (dB)

        STEREO = true;            % Enable stereo effect
        QUALITY = Quality.low;    % Reverb quality

        NEW_IR = true;            % Toggle to generate new IR
        SAVE_IR = true;           % Toggle to save IR to file

        MIX = 50;                 % Dry/Wet Mix (%)
        GAIN = 0;                 % Gain of output signal (dB)
    end

    properties (Constant)
        % Interface parameters
        PluginInterface = audioPluginInterface( ...
            'PluginName', 'Genetic Reverb', ...
            'VendorName', 'Edward Ly', ...
            'VendorVersion', '3.0.0', ...
            'InputChannels', 2, ...
            'OutputChannels', 2, ...
            audioPluginParameter('T60', ...
                'DisplayName', 'Decay Time', ...
                'DisplayNameLocation', 'Above', ...
                'Label', 's', ...
                'Layout', [2, 1; 5, 1], ...
                'Mapping', {'log', 0.2, 10}, ...
                'Style', 'rotaryknob'), ...
            audioPluginParameter('WARMTH', ...
                'DisplayName', 'Warmth', ...
                'DisplayNameLocation', 'Above', ...
                'Label', '%', ...
                'Layout', [2, 2; 5, 2], ...
                'Mapping', {'lin', 0, 100}, ...
                'Style', 'rotaryknob'), ...
            audioPluginParameter('ITDG', ...
                'DisplayName', 'Intimacy', ...
                'DisplayNameLocation', 'Above', ...
                'Label', 'ms', ...
                'Layout', [8, 1; 9, 1], ...
                'Mapping', {'log', 1, 100}, ...
                'Style', 'rotaryknob'), ...
            audioPluginParameter('C80', ...
                'DisplayName', 'Clarity', ...
                'DisplayNameLocation', 'Above', ...
                'Label', 'dB', ...
                'Layout', [8, 2; 9, 2], ...
                'Mapping', {'lin', -5, 5}, ...
                'Style', 'rotaryknob'), ...
            ...
            audioPluginParameter('QUALITY', ...
                'DisplayName', 'Quality', ...
                'DisplayNameLocation', 'Above', ...
                'Layout', [3, 3], ...
                'Mapping', {'enum', 'Low', 'Medium', 'High'}, ...
                'Style', 'dropdown'), ...
            audioPluginParameter('STEREO', ...
                'DisplayName', 'Mono/Stereo', ...
                'DisplayNameLocation', 'None', ...
                'Layout', [5, 3; 8, 3], ...
                'Mapping', {'enum', 'Mono', 'Stereo'}, ...
                'Style', 'vrocker'), ...
            ...
            audioPluginParameter('NEW_IR', ...
                'DisplayName', 'Generate Room', ...
                'DisplayNameLocation', 'Above', ...
                'Layout', [2, 4; 5, 4], ...
                'Mapping', {'enum', ' ', ' '}, ...
                'Style', 'vtoggle'), ...
            audioPluginParameter('SAVE_IR', ...
                'DisplayName', 'Save IR to File', ...
                'DisplayNameLocation', 'Above', ...
                'Layout', [8, 4; 9, 4], ...
                'Mapping', {'enum', ' ', ' '}, ...
                'Style', 'vtoggle'), ...
            ...
            audioPluginParameter('MIX', ...
                'DisplayName', 'Dry/Wet', ...
                'DisplayNameLocation', 'Above', ...
                'Label', '%', ...
                'Layout', [2, 5; 5, 5], ...
                'Mapping', {'lin', 0, 100}, ...
                'Style', 'rotaryknob'), ...
            audioPluginParameter('GAIN', ...
                'DisplayName', 'Output Gain', ...
                'DisplayNameLocation', 'Above', ...
                'Label', 'dB', ...
                'Layout', [8, 5; 9, 5], ...
                'Mapping', {'pow', 1/3, -60, 12}, ...
                'Style', 'rotaryknob'), ...
            ...
            audioPluginGridLayout( ...
                'RowHeight', [20, 20, 30, 30, 40, 20, 20, 50, 70], ...
                'ColumnWidth', [100, 100, 100, 100, 100], ...
                'RowSpacing', 0, ...
                'ColumnSpacing', 20, ...
                'Padding', [20, 20, 20, 20]))
    end

    properties (Nontunable)
        % Constant parameters
        IR_SAMPLE_RATE = 16000;   % Sample rate of generated IRs
        PARTITION_SIZE = 1024;    % Default partition length of conv filters

        % Specify full file path to directory where IRs will be saved here
        % (e.g. 'C:\Users\Edward\Downloads\')
        SAVE_IR_PATH = '';
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
        IR_NUM_SAMPLES = 24000;
        NUM_SAMPLES = 90000;

        % System objects for resampling IR to audio sample rate
        pFIR22050     % 16 kHz to 22.05 kHz
        pFIR32000     % 16 kHz to 32 kHz
        pFIR44100     % 16 kHz to 44.1 kHz
        pFIR48000     % 16 kHz to 48 kHz
        pFIR88200     % 16 kHz to 88.2 kHz
        pFIR96000     % 16 kHz to 96 kHz
        pFIR192000    % 16 kHz to 192 kHz
    end

    % Declared plugin methods for frequency-domain partitioned convolution
    methods (Access = protected)
        % Main process function
        out = stepImpl(plugin, in)

        % DSP initialization / setup
        setupImpl(plugin, ~)

        % Initialize/reset system object properties
        resetImpl(plugin)

        % Process parameter changes
        processTunedPropertiesImpl(plugin)
    end
end
