<?php

namespace Tests\Feature;

use App\Models\Task;
use App\Models\TaskInstance;
use App\Support\TaskScoring;
use Tests\TestCase;

class CustomTaskStepsTest extends TestCase
{
    private function scoredInstance(array $workItems = []): TaskInstance
    {
        $task = new Task(['scoring' => TaskScoring::normalize([
            'measure' => 'both',
            'steps' => [
                ['key' => 'custom_1', 'label' => 'Shade selection', 'max' => 5, 'enabled' => true, 'custom' => true],
                ['key' => 'custom_2', 'label' => 'Polishing', 'max' => 10, 'enabled' => true, 'custom' => true],
                ['key' => 'custom_3', 'label' => 'Off', 'max' => 10, 'enabled' => false, 'custom' => true],
            ],
        ])]);
        $instance = new TaskInstance(['work_items' => $workItems]);
        $instance->setRelation('task', $task);

        return $instance;
    }

    public function test_hand_added_steps_keep_their_flag(): void
    {
        $steps = $this->scoredInstance()->task->scoring['steps'];

        $this->assertTrue($steps[0]['custom']);
        $this->assertSame(25.0, TaskScoring::stepsMax(['steps' => $steps]) + 10);
    }

    public function test_hand_added_steps_score_the_entered_grade_up_to_their_max(): void
    {
        [$items, $total] = TaskScoring::pointsFromCaseSheet($this->scoredInstance(), ['custom_1' => 9, 'custom_2' => 7.5]);

        $this->assertSame(12.5, $total);
        $this->assertSame(['custom_1', 'custom_2'], array_column($items, 'step'));
        $this->assertSame([5.0, 7.5], array_column($items, 'points'));
    }

    public function test_saved_grades_are_kept_when_none_are_sent(): void
    {
        [, $total] = TaskScoring::pointsFromCaseSheet($this->scoredInstance([
            ['option' => 'Shade selection', 'step' => 'custom_1', 'points' => 4, 'custom' => true],
        ]));

        $this->assertSame(4.0, $total);
    }

    public function test_graded_checklist_parts_score_their_grade_up_to_their_max(): void
    {
        $task = new Task(['scoring' => TaskScoring::normalize([
            'measure' => 'count',
            'checklist' => [
                ['label' => 'Case sheet filling', 'scored' => true, 'max' => 10],
                ['label' => 'Photographs', 'scored' => false, 'max' => 10],
                ['label' => 'Study models', 'scored' => true, 'max' => 5],
            ],
        ])]);

        $this->assertSame(['label' => 'Photographs'], $task->scoring['checklist'][1]);

        [$items, $total] = TaskScoring::resolveWorkItems($task, [
            ['check' => 0, 'grade' => 8],
            ['check' => 1],
            ['check' => 2, 'grade' => 9],
        ]);

        $this->assertSame(13.0, $total);
        $this->assertSame([8.0, 0, 5.0], array_column($items, 'points'));
        $this->assertTrue($items[0]['scored']);
    }

    public function test_switched_off_kinds_of_work_cannot_be_recorded(): void
    {
        $task = new Task(['scoring' => TaskScoring::normalize([
            'measure' => 'both',
            'options' => [
                ['label' => 'Class I / III', 'points' => 10],
                ['label' => 'Class II MOD', 'points' => 20, 'enabled' => false],
            ],
        ])]);

        $this->assertTrue($task->scoring['options'][0]['enabled']);
        [, $total] = TaskScoring::resolveWorkItems($task, [['option' => 0, 'qty' => 2]]);
        $this->assertSame(20.0, $total);

        $this->expectException(\Illuminate\Validation\ValidationException::class);
        TaskScoring::resolveWorkItems($task, [['option' => 1, 'qty' => 1]]);
    }
}
