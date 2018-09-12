
require 'test_helper'
require 'rexml/document'

class IntegrationCtiControllerTest < ActionDispatch::IntegrationTest
  setup do

    Cti::Log.destroy_all

    Setting.set('cti_integration', true)
    Setting.set('cti_config', {
                  outbound: {
                    routing_table: [
                      {
                        dest: '41*',
                        caller_id: '41715880339000',
                      },
                      {
                        dest: '491714000000',
                        caller_id: '41715880339000',
                      },
                    ],
                    default_caller_id: '4930777000000',
                  },
                  inbound: {
                    block_caller_ids: [
                      {
                        caller_id: '491715000000',
                        note: 'some note',
                      }
                    ],
                    notify_user_ids: {
                      2 => true,
                      4 => false,
                    },
                  }
                },)

    groups = Group.where(name: 'Users')
    roles  = Role.where(name: %w[Agent])
    agent  = User.create_or_update(
      login: 'cti-agent@example.com',
      firstname: 'E',
      lastname: 'S',
      email: 'cti-agent@example.com',
      password: 'agentpw',
      active: true,
      roles: roles,
      groups: groups,
      updated_by_id: 1,
      created_by_id: 1,
    )

    customer1 = User.create_or_update(
      login: 'ticket-caller_id_cti-customer1@example.com',
      firstname: 'CallerId',
      lastname: 'Customer1',
      email: 'ticket-caller_id_cti-customer1@example.com',
      password: 'customerpw',
      active: true,
      phone: '+49 99999 222222',
      fax: '+49 99999 222223',
      mobile: '+4912347114711',
      note: 'Phone at home: +49 99999 222224',
      updated_by_id: 1,
      created_by_id: 1,
    )
    customer2 = User.create_or_update(
      login: 'ticket-caller_id_cti-customer2@example.com',
      firstname: 'CallerId',
      lastname: 'Customer2',
      email: 'ticket-caller_id_cti-customer2@example.com',
      password: 'customerpw',
      active: true,
      phone: '+49 99999 222222 2',
      updated_by_id: 1,
      created_by_id: 1,
    )
    customer3 = User.create_or_update(
      login: 'ticket-caller_id_cti-customer3@example.com',
      firstname: 'CallerId',
      lastname: 'Customer3',
      email: 'ticket-caller_id_cti-customer3@example.com',
      password: 'customerpw',
      active: true,
      phone: '+49 99999 222222 2',
      updated_by_id: 1,
      created_by_id: 1,
    )
    Cti::CallerId.rebuild

  end

  test 'token check' do
    params = 'event=newCall&direction=in&from=4912347114711&to=4930600000000&call_id=4991155921769858278-1&user%5B%5D=user+1&user%5B%5D=user+2'
    post '/api/v1/cti/not_existing_token', params: params
    assert_response(401)
    result = JSON.parse(@response.body)
    assert_equal(Hash, result.class)
    assert_equal('Invalid token, please contact your admin!', result['error'])
  end

  test 'basic call' do
    token = Setting.get('cti_token')

    # inbound - I
    params = 'event=newCall&direction=in&from=4912347114711&to=4930600000000&call_id=4991155921769858278-1&user%5B%5D=user+1&user%5B%5D=user+2'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)

    result = JSON.parse(@response.body)
    assert_equal(Hash, result.class)
    assert(result.blank?)

    # inbound - II - block caller
    params = 'event=newCall&direction=in&from=491715000000&to=4930600000000&call_id=4991155921769858278-2&user%5B%5D=user+1&user%5B%5D=user+2'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)

    result = JSON.parse(@response.body)
    assert_equal(Hash, result.class)
    assert_equal('reject', result['action'])
    assert_equal('busy', result['reason'])

    # outbound - I - set default_caller_id
    params = 'event=newCall&direction=out&from=4930600000000&to=4912347114711&call_id=8621106404543334274-3&user%5B%5D=user+1'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    result = JSON.parse(@response.body)
    assert_equal(Hash, result.class)
    assert_equal('dial', result['action'])
    assert_equal('4912347114711', result['number'])
    assert_equal('4930777000000', result['caller_id'])

    # outbound - II - set caller_id based on routing_table by explicite number
    params = 'event=newCall&direction=out&from=4930600000000&to=491714000000&call_id=8621106404543334274-4&user%5B%5D=user+1'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    result = JSON.parse(@response.body)
    assert_equal(Hash, result.class)
    assert_equal('dial', result['action'])
    assert_equal('491714000000', result['number'])
    assert_equal('41715880339000', result['caller_id'])

    # outbound - III - set caller_id based on routing_table by 41*
    params = 'event=newCall&direction=out&from=4930600000000&to=4147110000000&call_id=8621106404543334274-5&user%5B%5D=user+1'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    result = JSON.parse(@response.body)
    assert_equal(Hash, result.class)
    assert_equal('dial', result['action'])
    assert_equal('4147110000000', result['number'])
    assert_equal('41715880339000', result['caller_id'])

    # no config
    Setting.set('cti_config', {})
    params = 'event=newCall&direction=in&from=4912347114711&to=4930600000000&call_id=4991155921769858278-6&user%5B%5D=user+1&user%5B%5D=user+2'
    post "/api/v1/cti/#{token}", params: params
    assert_response(422)
    result = JSON.parse(@response.body)
    assert_equal(Hash, result.class)
    assert_equal('Feature not configured, please contact your admin!', result['error'])

  end

  test 'log call' do
    token = Setting.get('cti_token')

    # outbound - I - new call
    params = 'event=newCall&direction=out&from=4930600000000&to=4912347114711&call_id=1234567890-1&user%5B%5D=user+1'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-1')
    assert(log)
    assert_equal('4930777000000', log.from)
    assert_equal('4912347114711', log.to)
    assert_equal('out', log.direction)
    assert_equal('user 1', log.from_comment)
    assert_equal('CallerId Customer1', log.to_comment)
    assert_nil(log.comment)
    assert_equal('newCall', log.state)
    assert_equal(true, log.done)
    assert(log.initialized_at)
    assert_nil(log.start_at)
    assert_nil(log.end_at)
    assert_nil(log.duration_waiting_time)
    assert_nil(log.duration_talking_time)

    # outbound - I - hangup by agent
    params = 'event=hangup&direction=out&call_id=1234567890-1&cause=cancel'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-1')
    assert(log)
    assert_equal('4930777000000', log.from)
    assert_equal('4912347114711', log.to)
    assert_equal('out', log.direction)
    assert_equal('user 1', log.from_comment)
    assert_equal('CallerId Customer1', log.to_comment)
    assert_equal('cancel', log.comment)
    assert_equal('hangup', log.state)
    assert_equal(true, log.done)
    assert(log.initialized_at)
    assert_nil(log.start_at)
    assert(log.end_at)
    assert(log.duration_waiting_time)
    assert_nil(log.duration_talking_time)

    # outbound - II - new call
    params = 'event=newCall&direction=out&from=4930600000000&to=4912347114711&call_id=1234567890-2&user%5B%5D=user+1'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-2')
    assert(log)
    assert_equal('4930777000000', log.from)
    assert_equal('4912347114711', log.to)
    assert_equal('out', log.direction)
    assert_equal('user 1', log.from_comment)
    assert_equal('CallerId Customer1', log.to_comment)
    assert_nil(log.comment)
    assert_equal('newCall', log.state)
    assert_equal(true, log.done)
    assert(log.initialized_at)
    assert_nil(log.start_at)
    assert_nil(log.end_at)
    assert_nil(log.duration_waiting_time)
    assert_nil(log.duration_talking_time)

    # outbound - II - answer by customer
    params = 'event=answer&direction=out&call_id=1234567890-2&from=4930600000000&to=4912347114711'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-2')
    assert(log)
    assert_equal('4930777000000', log.from)
    assert_equal('4912347114711', log.to)
    assert_equal('out', log.direction)
    assert_equal('user 1', log.from_comment)
    assert_equal('CallerId Customer1', log.to_comment)
    assert_nil(log.comment)
    assert_equal('answer', log.state)
    assert_equal(true, log.done)
    assert(log.initialized_at)
    assert(log.start_at)
    assert_nil(log.end_at)
    assert(log.duration_waiting_time)
    assert_nil(log.duration_talking_time)

    # outbound - II - hangup by customer
    params = 'event=hangup&direction=out&call_id=1234567890-2&cause=normalClearing&from=4930600000000&to=4912347114711'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-2')
    assert(log)
    assert_equal('4930777000000', log.from)
    assert_equal('4912347114711', log.to)
    assert_equal('out', log.direction)
    assert_equal('user 1', log.from_comment)
    assert_equal('CallerId Customer1', log.to_comment)
    assert_equal('normalClearing', log.comment)
    assert_equal('hangup', log.state)
    assert_equal(true, log.done)
    assert(log.initialized_at)
    assert(log.start_at)
    assert(log.end_at)
    assert(log.duration_waiting_time)
    assert(log.duration_talking_time)

    # inbound - I - new call
    params = 'event=newCall&direction=in&to=4930600000000&from=4912347114711&call_id=1234567890-3&user%5B%5D=user+1'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-3')
    assert(log)
    assert_equal('4930600000000', log.to)
    assert_equal('4912347114711', log.from)
    assert_equal('in', log.direction)
    assert_equal('user 1', log.to_comment)
    assert_equal('CallerId Customer1', log.from_comment)
    assert_nil(log.comment)
    assert_equal('newCall', log.state)
    assert_equal(true, log.done)
    assert(log.initialized_at)
    assert_nil(log.start_at)
    assert_nil(log.end_at)
    assert_nil(log.duration_waiting_time)
    assert_nil(log.duration_talking_time)

    # inbound - I - answer by customer
    params = 'event=answer&direction=in&call_id=1234567890-3&to=4930600000000&from=4912347114711'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-3')
    assert(log)
    assert_equal('4930600000000', log.to)
    assert_equal('4912347114711', log.from)
    assert_equal('in', log.direction)
    assert_equal('user 1', log.to_comment)
    assert_equal('CallerId Customer1', log.from_comment)
    assert_nil(log.comment)
    assert_equal('answer', log.state)
    assert_equal(true, log.done)
    assert(log.initialized_at)
    assert(log.start_at)
    assert_nil(log.end_at)
    assert(log.duration_waiting_time)
    assert_nil(log.duration_talking_time)

    # inbound - I - hangup by customer
    params = 'event=hangup&direction=in&call_id=1234567890-3&cause=normalClearing&to=4930600000000&from=4912347114711'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-3')
    assert(log)
    assert_equal('4930600000000', log.to)
    assert_equal('4912347114711', log.from)
    assert_equal('in', log.direction)
    assert_equal('user 1', log.to_comment)
    assert_equal('CallerId Customer1', log.from_comment)
    assert_equal('normalClearing', log.comment)
    assert_equal('hangup', log.state)
    assert_equal(true, log.done)
    assert(log.initialized_at)
    assert(log.start_at)
    assert(log.end_at)
    assert(log.duration_waiting_time)
    assert(log.duration_talking_time)

    # inbound - II - new call
    params = 'event=newCall&direction=in&to=4930600000000&from=4912347114711&call_id=1234567890-4&user%5B%5D=user+1,user+2'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-4')
    assert(log)
    assert_equal('4930600000000', log.to)
    assert_equal('4912347114711', log.from)
    assert_equal('in', log.direction)
    assert_equal('user 1,user 2', log.to_comment)
    assert_equal('CallerId Customer1', log.from_comment)
    assert_nil(log.comment)
    assert_equal('newCall', log.state)
    assert_equal(true, log.done)
    assert(log.initialized_at)
    assert_nil(log.start_at)
    assert_nil(log.end_at)
    assert_nil(log.duration_waiting_time)
    assert_nil(log.duration_talking_time)

    # inbound - II - answer by voicemail
    params = 'event=answer&direction=in&call_id=1234567890-4&to=4930600000000&from=4912347114711&user=voicemail'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-4')
    assert(log)
    assert_equal('4930600000000', log.to)
    assert_equal('4912347114711', log.from)
    assert_equal('in', log.direction)
    assert_equal('voicemail', log.to_comment)
    assert_equal('CallerId Customer1', log.from_comment)
    assert_nil(log.comment)
    assert_equal('answer', log.state)
    assert_equal(true, log.done)
    assert(log.initialized_at)
    assert(log.start_at)
    assert_nil(log.end_at)
    assert(log.duration_waiting_time)
    assert_nil(log.duration_talking_time)

    # inbound - II - hangup by customer
    params = 'event=hangup&direction=in&call_id=1234567890-4&cause=normalClearing&to=4930600000000&from=4912347114711'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-4')
    assert(log)
    assert_equal('4930600000000', log.to)
    assert_equal('4912347114711', log.from)
    assert_equal('in', log.direction)
    assert_equal('voicemail', log.to_comment)
    assert_equal('CallerId Customer1', log.from_comment)
    assert_equal('normalClearing', log.comment)
    assert_equal('hangup', log.state)
    assert_equal(false, log.done)
    assert(log.initialized_at)
    assert(log.start_at)
    assert(log.end_at)
    assert(log.duration_waiting_time)
    assert(log.duration_talking_time)

    # inbound - III - new call
    params = 'event=newCall&direction=in&to=4930600000000&from=4912347114711&call_id=1234567890-5&user%5B%5D=user+1,user+2'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-5')
    assert(log)
    assert_equal('4930600000000', log.to)
    assert_equal('4912347114711', log.from)
    assert_equal('in', log.direction)
    assert_equal('user 1,user 2', log.to_comment)
    assert_equal('CallerId Customer1', log.from_comment)
    assert_nil(log.comment)
    assert_equal('newCall', log.state)
    assert_equal(true, log.done)
    assert(log.initialized_at)
    assert_nil(log.start_at)
    assert_nil(log.end_at)
    assert_nil(log.duration_waiting_time)
    assert_nil(log.duration_talking_time)

    # inbound - III - hangup by customer
    params = 'event=hangup&direction=in&call_id=1234567890-5&cause=normalClearing&to=4930600000000&from=4912347114711'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-5')
    assert(log)
    assert_equal('4930600000000', log.to)
    assert_equal('4912347114711', log.from)
    assert_equal('in', log.direction)
    assert_equal('user 1,user 2', log.to_comment)
    assert_equal('CallerId Customer1', log.from_comment)
    assert_equal('normalClearing', log.comment)
    assert_equal('hangup', log.state)
    assert_equal(false, log.done)
    assert(log.initialized_at)
    assert_nil(log.start_at)
    assert(log.end_at)
    assert(log.duration_waiting_time)
    assert_nil(log.duration_talking_time)

    # inbound - IV - new call
    params = 'event=newCall&direction=in&to=4930600000000&from=49999992222222&call_id=1234567890-6&user%5B%5D=user+1,user+2'
    post "/api/v1/cti/#{token}", params: params
    assert_response(200)
    log = Cti::Log.find_by(call_id: '1234567890-6')
    assert(log)
    assert_equal('4930600000000', log.to)
    assert_equal('49999992222222', log.from)
    assert_equal('in', log.direction)
    assert_equal('user 1,user 2', log.to_comment)
    assert_equal('CallerId Customer3,CallerId Customer2', log.from_comment)
    assert_not(log.preferences['to'])
    assert(log.preferences['from'])
    assert_nil(log.comment)
    assert_equal('newCall', log.state)
    assert_equal(true, log.done)
    assert(log.initialized_at)
    assert_nil(log.start_at)
    assert_nil(log.end_at)
    assert_nil(log.duration_waiting_time)
    assert_nil(log.duration_talking_time)

    # get caller list
    get '/api/v1/cti/log'
    assert_response(401)

    customer2 = User.lookup(login: 'ticket-caller_id_cti-customer2@example.com')
    customer3 = User.lookup(login: 'ticket-caller_id_cti-customer3@example.com')

    headers = { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials('cti-agent@example.com', 'agentpw')
    get '/api/v1/cti/log', headers: headers.merge('Authorization' => credentials)
    assert_response(200)
    result = JSON.parse(@response.body)
    assert_equal(result['list'].class, Array)
    assert_equal(6, result['list'].count)
    assert(result['assets'])
    assert(result['assets']['User'])
    assert(result['assets']['User'][customer2.id.to_s])
    assert(result['assets']['User'][customer3.id.to_s])
    assert_equal('1234567890-6', result['list'][0]['call_id'])
    assert_equal('1234567890-5', result['list'][1]['call_id'])
    assert_equal('1234567890-4', result['list'][2]['call_id'])
    assert_equal('1234567890-3', result['list'][3]['call_id'])
    assert_equal('1234567890-2', result['list'][4]['call_id'])
    assert_equal('hangup', result['list'][4]['state'])
    assert_equal('4930777000000', result['list'][4]['from'])
    assert_equal('user 1', result['list'][4]['from_comment'])
    assert_equal('4912347114711', result['list'][4]['to'])
    assert_equal('CallerId Customer1', result['list'][4]['to_comment'])
    assert_equal('normalClearing', result['list'][4]['comment'])
    assert_equal('hangup', result['list'][4]['state'])
    assert_equal('1234567890-1', result['list'][5]['call_id'])

  end

end
