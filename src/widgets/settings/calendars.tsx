import { Dropdown } from "components/Dropdown";
import { Input } from "components/Input";
import { MySwitch } from "components/MySwitch";
import { SolButton } from "components/SolButton";
import { observer } from "mobx-react-lite";
import { useEffect, useState } from "react";
import { ScrollView, Text, TouchableOpacity, View } from "react-native";
import { useStore } from "store";

// Text input that only saves on blur / Enter, so partial input isn't parsed mid-typing
const CommitInput = ({
	value: stored,
	onCommit,
	placeholder,
	className,
}: {
	value: string;
	onCommit: (text: string) => void;
	placeholder: string;
	className?: string;
}) => {
	const [value, setValue] = useState(stored);

	useEffect(() => {
		setValue(stored);
	}, [stored]);

	const commit = () => {
		onCommit(value);
	};

	return (
		<Input
			bordered
			value={value}
			onChangeText={setValue}
			onBlur={commit}
			onSubmitEditing={commit}
			placeholder={placeholder}
			className={className}
			autoCorrect={false}
			autoCapitalize="none"
		/>
	);
};

const SOUND_OPTIONS = [
	"none",
	"Basso",
	"Blow",
	"Bottle",
	"Frog",
	"Funk",
	"Glass",
	"Hero",
	"Morse",
	"Ping",
	"Pop",
	"Purr",
	"Sosumi",
	"Submarine",
	"Tink",
].map((sound) => ({
	label: sound === "none" ? "None" : sound,
	value: sound,
}));

const MeetingReminders = observer(({ disabled }: { disabled: boolean }) => {
	const store = useStore();
	const reminders = store.calendar.meetingReminders;
	const setOption = store.calendar.setMeetingReminderOption;

	return (
		<View className="p-3 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder z-10">
			<View className="flex-row items-center">
				<View className="flex-1">
					<Text className="text-sm text">Meeting Reminders</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						Remind before events that pass the menu bar filters below.
					</Text>
				</View>
				<MySwitch
					value={reminders.enabled}
					onValueChange={(v) => setOption("enabled", v)}
					disabled={disabled}
				/>
			</View>

			<View className="border-t border-lightBorder dark:border-darkBorder" />
			<View className="flex-row items-center gap-2">
				<View className="flex-1">
					<Text className="text-sm text">Remind Before (minutes)</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						Comma-separated, e.g. 5, 10, 15.
					</Text>
				</View>
				<CommitInput
					className="w-40"
					value={reminders.thresholds.join(", ")}
					onCommit={store.calendar.setMeetingReminderThresholds}
					placeholder="5, 10, 15"
				/>
			</View>

			<View className="border-t border-lightBorder dark:border-darkBorder" />
			<View className="flex-row items-center z-50">
				<View className="flex-1">
					<Text className="text-sm text">Delivery</Text>
					{reminders.delivery === "system" && (
						<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
							To keep reminders on screen, set Sol's style to "Persistent" in
							System Settings → Notifications.
						</Text>
					)}
				</View>
				<Dropdown
					className="w-48"
					value={reminders.delivery}
					onValueChange={(v) =>
						setOption("delivery", v as "overlay" | "system")
					}
					options={[
						{ label: "Sol overlay", value: "overlay" },
						{ label: "macOS notification", value: "system" },
					]}
				/>
			</View>

			{reminders.delivery === "overlay" && (
				<>
					<View className="border-t border-lightBorder dark:border-darkBorder" />
					<View className="flex-row items-center z-40">
						<Text className="flex-1 text-sm text">Color</Text>
						<Dropdown
							className="w-48"
							value={reminders.theme}
							onValueChange={(v) =>
								setOption("theme", v as MeetingReminderConfig["theme"])
							}
							options={[
								{ label: "System (translucent)", value: "system" },
								{ label: "Blue", value: "blue" },
								{ label: "Purple", value: "purple" },
								{ label: "Orange", value: "orange" },
								{ label: "Red", value: "red" },
								{ label: "Green", value: "green" },
							]}
						/>
					</View>

					<View className="border-t border-lightBorder dark:border-darkBorder" />
					<View className="flex-row items-center z-30">
						<Text className="flex-1 text-sm text">Position</Text>
						<Dropdown
							className="w-48"
							value={reminders.position}
							onValueChange={(v) =>
								setOption("position", v as MeetingReminderConfig["position"])
							}
							options={[
								{ label: "Top left", value: "topLeft" },
								{ label: "Top center", value: "topCenter" },
								{ label: "Top right", value: "topRight" },
								{ label: "Center", value: "center" },
								{ label: "Bottom left", value: "bottomLeft" },
								{ label: "Bottom right", value: "bottomRight" },
							]}
						/>
					</View>

					<View className="border-t border-lightBorder dark:border-darkBorder" />
					<View className="flex-row items-center z-20">
						<Text className="flex-1 text-sm text">Size</Text>
						<Dropdown
							className="w-48"
							value={reminders.size}
							onValueChange={(v) =>
								setOption("size", v as MeetingReminderConfig["size"])
							}
							options={[
								{ label: "Compact", value: "compact" },
								{ label: "Large", value: "large" },
							]}
						/>
					</View>
				</>
			)}

			<View className="border-t border-lightBorder dark:border-darkBorder" />
			<View className="flex-row items-center z-10">
				<Text className="flex-1 text-sm text">Sound</Text>
				<Dropdown
					className="w-48"
					value={reminders.sound}
					onValueChange={(v) => setOption("sound", v as string)}
					options={SOUND_OPTIONS}
				/>
			</View>

			<View className="border-t border-lightBorder dark:border-darkBorder" />
			<View className="flex-row items-center justify-between">
				<Text className="text-xxs text-neutral-500 dark:text-neutral-400 flex-1">
					Shows a sample reminder with your current settings.
				</Text>
				<SolButton
					title="Test notification"
					onPress={store.calendar.showTestMeetingReminder}
				/>
			</View>
		</View>
	);
});

export const Calendars = observer(() => {
	const store = useStore();
	const hasCalendarAccess =
		store.calendar.calendarAuthorizationStatus === "authorized";

	return (
		<ScrollView
			showsVerticalScrollIndicator={false}
			automaticallyAdjustContentInsets
			className="flex-1"
			contentContainerClassName="p-5 gap-2"
		>
			<View className="p-3 subBg gap-3 rounded-lg border border-lightBorder dark:border-darkBorder">
				<View className="flex-row items-center">
					<View className="flex-1">
						<Text className="text-sm text">Show In-App Calendar</Text>
						<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
							Display calendar events inside Sol.
						</Text>
					</View>
					<MySwitch
						value={store.ui.calendarEnabled}
						onValueChange={store.ui.setCalendarEnabled}
					/>
				</View>
				<View className="border-t border-lightBorder dark:border-darkBorder" />
				<View className="flex-row items-center">
					<View className="flex-1">
						<Text className="text-sm text">
							Show Upcoming Event In Menu Bar
						</Text>
						<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
							Show the next event title and time in the menu bar.
						</Text>
					</View>
					<MySwitch
						value={store.ui.showUpcomingEvent}
						onValueChange={store.ui.setShowUpcomingEvent}
					/>
				</View>
			</View>

			<MeetingReminders disabled={!hasCalendarAccess} />

			<View className="p-3 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
				<Text className="text-sm text">Calendar Sources</Text>

				{!hasCalendarAccess && (
					<Text className="text-xs text-neutral-500 dark:text-neutral-400 mt-1">
						Calendar access is not granted yet. Enable calendar access in system
						settings to manage sources.
					</Text>
				)}
				<View className="flex-row items-center justify-between">
					<Text className="text-xs text-neutral-500 dark:text-neutral-400">
						Selected {store.calendar.selectedCalendarIds.length} of{" "}
						{store.calendar.calendars.length}
					</Text>
					<View className="flex-row items-center gap-3">
						<TouchableOpacity
							onPress={store.calendar.selectAllCalendars}
							disabled={
								!hasCalendarAccess || store.calendar.calendars.length === 0
							}
						>
							<Text className="text-blue-500 text-xs">Select all</Text>
						</TouchableOpacity>
						<TouchableOpacity
							onPress={store.calendar.clearCalendarSelection}
							disabled={
								!hasCalendarAccess || store.calendar.calendars.length === 0
							}
						>
							<Text className="text-blue-500 text-xs">Clear</Text>
						</TouchableOpacity>
					</View>
				</View>

				{store.calendar.calendars.length === 0 && (
					<Text className="text-xs text-neutral-500 dark:text-neutral-400">
						No calendars found.
					</Text>
				)}

				{store.calendar.calendars.map((calendar, idx) => {
					const isSelected = store.calendar.isCalendarSelected(calendar.id);
					return (
						<View key={calendar.id}>
							{idx > 0 && (
								<View className="border-t border-lightBorder dark:border-darkBorder" />
							)}
							<View className="flex-row items-center py-2">
								<Text className="text-sm text flex-1">{calendar.title}</Text>
								<MySwitch
									value={isSelected}
									onValueChange={() => {
										store.calendar.toggleCalendarSelection(calendar.id);
									}}
									disabled={!hasCalendarAccess}
								/>
							</View>
						</View>
					);
				})}
			</View>

			<View className="p-3 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
				<Text className="text-sm text">Menu Bar Filters</Text>
				<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
					Choose which events can appear as the upcoming event in the menu bar.
					These don't affect the in-app calendar.
				</Text>

				<View className="border-t border-lightBorder dark:border-darkBorder" />
				<View className="flex-row items-center">
					<View className="flex-1">
						<Text className="text-sm text">Only Events With Meeting Link</Text>
						<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
							Hide events without a Zoom, Meet, Teams or similar link.
						</Text>
					</View>
					<MySwitch
						value={store.calendar.menuBarRequireMeetingLink}
						onValueChange={store.calendar.setMenuBarRequireMeetingLink}
					/>
				</View>

				<View className="border-t border-lightBorder dark:border-darkBorder" />
				<View className="gap-1">
					<Text className="text-sm text">Exclude Titles Containing</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						Comma-separated, case-insensitive.
					</Text>
					<CommitInput
						value={store.calendar.menuBarExcludeKeywords.join(", ")}
						onCommit={store.calendar.setMenuBarExcludeKeywords}
						placeholder="e.g. Focus, Lunch, OOO"
					/>
				</View>

				<View className="border-t border-lightBorder dark:border-darkBorder" />
				<View className="flex-row items-center justify-between">
					<Text className="text-xs text-neutral-500 dark:text-neutral-400">
						Menu bar calendars:{" "}
						{store.calendar.menuBarCalendarIds === null
							? "all"
							: `${store.calendar.menuBarCalendarIds.length} of ${store.calendar.calendars.length}`}
					</Text>
					<View className="flex-row items-center gap-3">
						<TouchableOpacity
							onPress={store.calendar.selectAllMenuBarCalendars}
							disabled={!hasCalendarAccess}
						>
							<Text className="text-blue-500 text-xs">Select all</Text>
						</TouchableOpacity>
						<TouchableOpacity
							onPress={store.calendar.clearMenuBarCalendars}
							disabled={!hasCalendarAccess}
						>
							<Text className="text-blue-500 text-xs">Clear</Text>
						</TouchableOpacity>
					</View>
				</View>

				{store.calendar.calendars.map((calendar, idx) => (
					<View key={calendar.id}>
						{idx > 0 && (
							<View className="border-t border-lightBorder dark:border-darkBorder" />
						)}
						<View className="flex-row items-center py-2">
							<Text className="text-sm text flex-1">{calendar.title}</Text>
							<MySwitch
								value={store.calendar.isMenuBarCalendarSelected(calendar.id)}
								onValueChange={() => {
									store.calendar.toggleMenuBarCalendar(calendar.id);
								}}
								disabled={!hasCalendarAccess}
							/>
						</View>
					</View>
				))}
			</View>
		</ScrollView>
	);
});
