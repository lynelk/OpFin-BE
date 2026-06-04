<?php

namespace App\Http\Requests;

use App\Models\User;

class UpdateLoanApplicationStatusRequest extends BaseFormRequest
{
    public function authorize(): bool
    {
        $user = $this->user();

        return (bool) ($user?->is_admin || $user?->hasAnyRole([
            User::ROLE_PLATFORM_ADMIN,
            User::ROLE_OPERATIONS,
        ]));
    }

    public function rules(): array
    {
        return [
            'status' => 'required|in:Approved,Rejected,Disbursed,Cancelled',
        ];
    }
}
