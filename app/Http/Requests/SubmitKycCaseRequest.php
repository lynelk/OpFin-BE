<?php

namespace App\Http\Requests;

class SubmitKycCaseRequest extends BaseFormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'national_id' => 'required|string|max:64',
            'provider' => 'nullable|string|max:64',
            'provider_reference' => 'nullable|string|max:128',
            'evidence' => 'nullable|array',
        ];
    }
}
