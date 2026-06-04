<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class FormRequestValidationTest extends TestCase
{
    use RefreshDatabase;

    public function test_register_rejects_weak_password(): void
    {
        $this->postJson('/api/register', [
            'name' => 'Test User',
            'phone' => '256700000001',
            'password' => 'weak',
            'password_confirmation' => 'weak',
        ])->assertStatus(422)->assertJsonPath('success', false);
    }

    public function test_register_rejects_duplicate_phone(): void
    {
        User::factory()->create(['phone' => '256700000099']);

        $this->postJson('/api/register', [
            'name' => 'Another User',
            'phone' => '256700000099',
            'password' => 'Str0ng!P@ssword1',
            'password_confirmation' => 'Str0ng!P@ssword1',
        ])->assertStatus(422)->assertJsonPath('success', false);
    }

    public function test_login_rejects_missing_credentials(): void
    {
        $this->postJson('/api/login', [])
            ->assertStatus(422)
            ->assertJsonPath('success', false);
    }

    public function test_kyc_submit_rejects_missing_national_id(): void
    {
        $customer = User::factory()->create(['role' => User::ROLE_CUSTOMER]);
        Sanctum::actingAs($customer);

        $this->postJson('/api/kyc/cases', [
            'provider' => 'manual',
        ])->assertStatus(422)->assertJsonPath('success', false);
    }

    public function test_loan_application_rejects_missing_required_fields(): void
    {
        $customer = User::factory()->create([
            'role' => User::ROLE_CUSTOMER,
            'nin_status' => 'VALID',
        ]);
        Sanctum::actingAs($customer);

        $this->postJson('/api/loan-applications', [
            'amount' => 250000,
        ])->assertStatus(422)->assertJsonPath('success', false);
    }

    public function test_loan_status_update_forbidden_for_customers(): void
    {
        $customer = User::factory()->create(['role' => User::ROLE_CUSTOMER]);
        Sanctum::actingAs($customer);

        $this->postJson('/api/loan-applications/1/status', [
            'status' => 'Approved',
        ])->assertStatus(403);
    }

    public function test_generate_otp_rejects_missing_phone(): void
    {
        $this->postJson('/api/generate-otp', [])
            ->assertStatus(422)
            ->assertJsonPath('success', false);
    }

    public function test_consent_grant_rejects_missing_purpose(): void
    {
        $customer = User::factory()->create(['role' => User::ROLE_CUSTOMER]);
        Sanctum::actingAs($customer);

        $this->postJson('/api/consents', [
            'policy_version' => 'credit-consent-v1',
        ])->assertStatus(422)->assertJsonPath('success', false);
    }
}
