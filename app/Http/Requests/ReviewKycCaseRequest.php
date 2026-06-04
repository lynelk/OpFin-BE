<?php

namespace App\Http\Requests;

use App\Models\KycCase;
use App\Models\User;
use Illuminate\Validation\Rule;

class ReviewKycCaseRequest extends BaseFormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->hasAnyRole([
            User::ROLE_PLATFORM_ADMIN,
            User::ROLE_OPERATIONS,
            User::ROLE_SUPPORT,
        ]) ?? false;
    }

    public function rules(): array
    {
        return [
            'status' => ['required', Rule::in([KycCase::STATUS_VERIFIED, KycCase::STATUS_REJECTED])],
            'review_notes' => 'nullable|string|max:1000',
            'risk_flags' => 'nullable|array',
            'expires_at' => 'nullable|date|after:today',
        ];
    }
}
