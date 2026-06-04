<?php

namespace App\Http\Requests;

class InitiateRepaymentRequest extends BaseFormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'amount' => 'required|numeric|min:1',
        ];
    }
}
