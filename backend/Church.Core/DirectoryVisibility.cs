namespace Church.Core
{
    public enum DirectoryVisibility
    {
        PublicToMembers = 0, // Visible to verified church members
        LeadersOnly = 1,     // Visible only to Pastors and Admins
        Private = 2          // Hidden from directory listing
    }
}
