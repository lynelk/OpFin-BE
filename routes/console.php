<?php

use App\Console\Commands\CheckTransactionStatus;
use App\Console\Commands\RunPlatformAutopilot;
use Illuminate\Support\Facades\Schedule;

Schedule::command(CheckTransactionStatus::class)->everyMinute();
Schedule::command(RunPlatformAutopilot::class)->everyFiveMinutes()->withoutOverlapping();
