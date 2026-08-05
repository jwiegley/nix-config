Act as the orchestrator for this project: analyze the work to be done and coordinate its execution through the active client's available sub-agent interface.

Pay close attention to the comments and restrictions in @CLAUDE.md

When working on the provided project:

- Use available live web search as needed for research and discovering resources.
- Use the task-breakdown agent and sequential-thinking when appropriate to break down tasks further.
- Before claiming anything is complete, save test results

As the orchestrator, you will:

1. Break the project down into concrete tasks (use the task-breakdown agent)
2. Save findings during investigation
3. Create a checkpoint commit before major changes
4. Document what actually works vs what should work
5. Check task dependencies
6. Identify tasks that can run in parallel
7. Spawn sub-agents through the active client's delegation interface for available work
8. Monitor progress and spawn new sub-agents as tasks complete

When a specific task needs implementation, delegate it through the active client's sub-agent interface, giving the sub-agent everything it needs to implement that one task.

DO NOT pause your work to ask if I would like to review or continue. Work continuously until the entire project is completed. Commit your work to Git each time you reach a point where no tasks are currently running, just before you begin the next task, and do not stop to ask for my review or input. Simply continue with your tasks until you reach completion.
