<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\ReviewKycCaseRequest;
use App\Http\Requests\SubmitKycCaseRequest;
use App\Models\KycCase;
use App\Services\AuditLogger;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ProductionKycController extends Controller
{
    public function __construct(private readonly AuditLogger $auditLogger) {}

    public function show(Request $request): JsonResponse
    {
        return ApiResponse::success('KYC status loaded.', [
            'latest_case' => KycCase::where('user_id', $request->user()->id)->latest()->first(),
        ]);
    }

    public function submit(SubmitKycCaseRequest $request): JsonResponse
    {
        $case = KycCase::create([
            ...$request->validated(),
            'user_id' => $request->user()->id,
            'status' => KycCase::STATUS_PENDING_REVIEW,
            'submitted_at' => now(),
        ]);

        $this->auditLogger->record('kyc.submitted', $request->user(), $case, [], $request);

        return ApiResponse::success('KYC case submitted for review.', ['kyc_case' => $case], 201);
    }

    public function review(KycCase $case, ReviewKycCaseRequest $request): JsonResponse
    {
        $case->update([
            ...$request->validated(),
            'reviewed_by' => $request->user()->id,
            'reviewed_at' => now(),
        ]);

        $case->user->update(['nin_status' => $case->status === KycCase::STATUS_VERIFIED ? 'VALID' : 'REJECTED']);
        $this->auditLogger->record('kyc.reviewed', $request->user(), $case, ['status' => $case->status], $request);

        return ApiResponse::success('KYC case reviewed.', ['kyc_case' => $case->fresh()]);
    }
}
