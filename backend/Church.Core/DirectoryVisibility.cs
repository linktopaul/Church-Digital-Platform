namespace Church.Core
{
    public enum DirectoryVisibility
    {
        Private = 0,          // Default: Hidden from directory until member opts in
        PublicToMembers = 1,  // Visible to verified church members
        LeadersOnly = 2       // Visible only to Pastors and Admins
    }
}
