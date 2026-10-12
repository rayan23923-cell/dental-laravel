<?php

namespace Tests\Feature;

use Tests\TestCase;

class CaptivePortalTest extends TestCase
{
    public function test_a_new_device_is_sent_to_the_setup_page_once(): void
    {
        config(['app.url' => 'https://clinic.lan']);
        $server = ['REMOTE_ADDR' => '192.168.68.50'];

        $this->withServerVariables($server)->get('/captive-check?h=connectivitycheck.gstatic.com&p=/generate_204')
            ->assertRedirect('http://clinic.lan/portal');
        $this->withServerVariables($server)->get('/portal')->assertRedirect('http://clinic.lan/setup');

        // Seen: the checks now say "connected", in each device's own format.
        $this->withServerVariables($server)->get('/captive-check?h=connectivitycheck.gstatic.com&p=/generate_204')->assertNoContent();
        $this->withServerVariables($server)->get('/captive-check?h=captive.apple.com&p=/hotspot-detect.html')->assertOk()->assertSee('Success');
        $this->withServerVariables($server)->get('/captive-check?h=www.msftconnecttest.com&p=/connecttest.txt')->assertSeeText('Microsoft Connect Test');

        // Another device on the network still gets the page.
        $this->withServerVariables(['REMOTE_ADDR' => '192.168.68.51'])->get('/captive-check?h=captive.apple.com&p=/hotspot-detect.html')
            ->assertRedirect('http://clinic.lan/portal');
    }
}
