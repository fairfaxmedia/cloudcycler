require 'minitest/autorun'
require 'cloud/cycler/schedule'

class TestSchedule < Minitest::Test
  [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday].each_with_index do |day, idx|
    active_string   = 'MTWTFSS 0800-1800'
    inactive_string = '------- 0800-1800'

    reference_date = "1900-01-#{idx+1}" # 1900-01-01 happens to be a Monday
    ch = day.to_s.chars.first.upcase


    define_method("test_string_#{day}_roundtrip") do
      Time.stub :now, Time.parse("#{reference_date} 12:00") do
        sched = Cloud::Cycler::Schedule.parse(active_string)
        assert_equal sched.to_s, active_string

        test_string = inactive_string.dup
        test_string[idx] = ch

        sched = Cloud::Cycler::Schedule.parse(test_string)
        assert_equal sched.to_s, test_string
      end
    end

    define_method("test_parsing_#{day}_on_days") do
      Time.stub :now, Time.parse("#{reference_date} 12:00") do
        sched = Cloud::Cycler::Schedule.parse(active_string)
        assert sched.active?

        test_string = inactive_string.dup
        test_string[idx] = ch

        sched = Cloud::Cycler::Schedule.parse(test_string)
        assert sched.active?
      end
    end

    define_method("test_parsing_#{day}_off_days") do
      Time.stub(:now, Time.parse("#{reference_date} 00:00")) do
        sched = Cloud::Cycler::Schedule.parse(inactive_string)
        assert !sched.active?

        test_string = active_string.dup
        test_string[idx] = '-'

        sched = Cloud::Cycler::Schedule.parse(test_string)
        assert !sched.active?
      end
    end

    define_method("test_parsing_#{day}_invalid_days") do
      Time.stub(:now, Time.parse("#{reference_date} 00:00")) do
        invalid_string = active_string.dup
        invalid_string[idx] = 'X'
        assert_raises Cloud::Cycler::InvalidSchedule do
          Cloud::Cycler::Schedule.parse(invalid_string)
        end

        invalid_string = inactive_string.dup
        invalid_string[idx] = 'X'
        assert_raises Cloud::Cycler::InvalidSchedule do
          Cloud::Cycler::Schedule.parse(invalid_string)
        end
      end
    end

    define_method("test_parsing_#{day}_before_hours") do
      Time.stub(:now, Time.parse("#{reference_date} 00:00")) do
        sched = Cloud::Cycler::Schedule.parse(active_string)
        assert !sched.active?

        test_string = inactive_string.dup
        test_string[idx] = ch

        sched = Cloud::Cycler::Schedule.parse(test_string)
        assert !sched.active?
      end
    end

    define_method("test_parsing_#{day}_after_hours") do
      Time.stub(:now, Time.parse("#{reference_date} 23:59")) do
        sched = Cloud::Cycler::Schedule.parse(active_string)
        assert !sched.active?

        test_string = inactive_string.dup
        test_string[idx] = ch

        sched = Cloud::Cycler::Schedule.parse(test_string)
        assert !sched.active?
      end
    end
  end
end
